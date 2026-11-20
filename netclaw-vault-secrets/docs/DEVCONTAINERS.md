# VS Code Dev Containers → HashiCorp Vault

Transition guide for local and GitLab-adjacent workflows where Dev Containers today rely on committed `.env` files, bind-mounted secret files, or plaintext vars for Ansible, NetBox APIs, and device access.

**Rule:** the image and git tree hold **tooling only**. Secrets enter the container at start time from Vault (or from a short-lived host env that came from Vault).

---

## Target pattern

```
Host (engineer laptop / workstation)
  → authenticates to Vault (OIDC, token, or AppRole)
  → exports VAULT_ADDR + VAULT_TOKEN (or role_id/secret_id)
  → Dev Container remoteEnv / mount picks them up
  → Ansible lookups, scripts, NetClaw tooling use Vault
```

| Before | After |
|--------|--------|
| `.env` in repo or workspace with passwords | Paths + `VAULT_ADDR` only in git |
| `containerEnv` hardcoding tokens | `remoteEnv` from `${localEnv:...}` |
| Bind-mount `~/.ssh` + shared password files | Vault KV / SSH engine at runtime |
| Same long-lived token for months | Login script / short TTL token |

---

## 1. What to remove from Dev Container projects

Search the repo and `.devcontainer/` for:

- [ ] `.env`, `.env.local`, `*.pem`, password files tracked or documented as “copy this”
- [ ] `containerEnv` / `remoteEnv` with literal secrets
- [ ] Dockerfile `ENV` lines with tokens
- [ ] Instructions like “paste the enable password into `group_vars`”
- [ ] Bind mounts of team-shared credential directories

Replace with: Vault address, auth method name, and **path conventions** only.

---

## 2. Host-side: get a Vault token before opening the folder

### Option A — Interactive CLI (good default)

```bash
export VAULT_ADDR=https://vault.example.local:8200
# vault login -method=oidc   # preferred for humans
# or: vault login             # token from break-glass / userpass+MFA
export VAULT_TOKEN=$(vault print token)   # if using token helper
# often ~/.vault-token is written automatically after vault login
```

Ensure the integrated terminal inherits the host environment (VS Code setting **Terminal › Integrated: Inherit Env**).

### Option B — AppRole for a dedicated “dev” role (lab only)

```bash
export VAULT_ADDR=https://vault.example.local:8200
export VAULT_ROLE_ID=...
export VAULT_SECRET_ID=...   # from password manager / Vault agent, not git
export VAULT_TOKEN=$(vault write -field=token auth/approle/login \
  role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")
```

Use a **dev/lab** policy (`ansible-dev` / `netclaw-read`), never prod-wide admin.

### Option C — Vault Agent on the host

Run Vault Agent with auto-auth; write a wrapped token or render env files into a host path that the Dev Container mounts read-only.

---

## 3. `devcontainer.json` patterns

### Pass Vault addressing + token from the host

```json
{
  "name": "network-automation",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:1": {}
  },
  "remoteEnv": {
    "VAULT_ADDR": "${localEnv:VAULT_ADDR}",
    "VAULT_TOKEN": "${localEnv:VAULT_TOKEN}",
    "VAULT_NAMESPACE": "${localEnv:VAULT_NAMESPACE}",
    "ANSIBLE_HASHI_VAULT_ADDR": "${localEnv:VAULT_ADDR}",
    "ANSIBLE_HASHI_VAULT_TOKEN": "${localEnv:VAULT_TOKEN}"
  },
  "mounts": [
    "source=${localEnv:HOME}/.vault-token,target=/home/vscode/.vault-token,type=bind,readonly"
  ],
  "postCreateCommand": "bash .devcontainer/post-create.sh"
}
```

Notes:

- Prefer `remoteEnv` over `containerEnv` for secrets so they apply to the VS Code server/terminals without baking into image metadata unnecessarily.
- `${localEnv:VAULT_TOKEN}` is empty if the host did not export it — fail closed in `post-create` / playbooks rather than falling back to plaintext.
- Mounting `~/.vault-token` helps CLI/`hvac` when env injection is awkward; keep the file mode `600` on the host.
- **Do not** commit a filled `VAULT_TOKEN` into `devcontainer.json`.

Full example: [`../examples/devcontainer/devcontainer.json`](../examples/devcontainer/devcontainer.json).

### `post-create.sh` (tooling only)

```bash
#!/usr/bin/env bash
set -euo pipefail
ansible-galaxy collection install -r requirements.yml
pip install -r requirements.txt
command -v vault >/dev/null || echo "Install vault CLI in Dockerfile/feature if needed"
if [[ -z "${VAULT_ADDR:-}" ]]; then
  echo "WARN: VAULT_ADDR not set — secrets lookups will fail" >&2
fi
```

Install the Vault CLI in the image (package or feature) so engineers can `vault kv get` while debugging **paths** (avoid dumping prod secrets into the terminal history).

---

## 4. Running Ansible inside the container

With `VAULT_ADDR` + `VAULT_TOKEN` present:

```bash
ansible-playbook -i inventory/lab playbooks/site.yml
```

Lookups use `community.hashi_vault` as in [ANSIBLE.md](ANSIBLE.md). No `ansible-vault` password prompt for migrated vars.

### Task / launch configs

If you use VS Code tasks, reference env vars — do not put secrets in `.vscode/settings.json`:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "ansible: lab playbook",
      "type": "shell",
      "command": "ansible-playbook -i inventory/lab playbooks/site.yml",
      "options": { "env": { "VAULT_ADDR": "${env:VAULT_ADDR}" } },
      "problemMatcher": []
    }
  ]
}
```

---

## 5. GitLab + Dev Containers together

| Workflow | Secret path |
|----------|-------------|
| CI pipeline on Runner | GitLab JWT → Vault ([GITLAB.md](GITLAB.md)) |
| Local Dev Container | Human OIDC/token → Vault (this doc) |
| Same playbooks | Identical Vault **paths**; different **auth** |

Do not copy CI JWT tokens into Dev Containers. Engineers use human or lab AppRole identities so audit trails stay meaningful.

---

## 6. Migration steps (per Dev Container project)

1. **List** secrets the container needs (Ansible, NetBox, cloud APIs, lab enable passwords).
2. **Ensure** each exists in Vault under the standard path layout.
3. **Strip** secrets from `.env` / Dockerfile / `devcontainer.json`.
4. **Add** `remoteEnv` + optional `~/.vault-token` mount.
5. **Document** in the project README: “Run `vault login` (or export token) on the host before Reopen in Container.”
6. **Add** a smoke task: `vault token lookup` and one `vault kv get` / Ansible dry-run in lab.
7. **Rotate** any secret that ever lived in git history (treat as burned).

---

## 7. Hardening checklist

- [ ] Dev Container network can reach `VAULT_ADDR:8200` (VPN/DNS/CA trust)
- [ ] Lab policy for humans/dev AppRole; prod access break-glass or separate role
- [ ] No Docker image published with tokens in layers (`docker history`)
- [ ] Disable committing `.env` via `.gitignore`; provide `.env.example` with **names only**
- [ ] Prefer read-only mounts for token files
- [ ] Logout / revoke token at end of day for shared workstations

Example `.env.example`:

```bash
VAULT_ADDR=https://vault.example.local:8200
# VAULT_TOKEN=   # set via vault login — do not commit
# VAULT_NAMESPACE=
```

---

## 8. Acceptance criteria

- Container rebuilds and Ansible lab run succeed **without** any password file in the git tree
- `VAULT_TOKEN` absent ⇒ playbook fails clearly (no silent plaintext fallback)
- Vault audit shows the engineer’s identity (OIDC/entity) or lab AppRole — not a shared root token
- Same Vault paths work from Dev Container and GitLab CI ([ANSIBLE.md](ANSIBLE.md))
