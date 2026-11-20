# Ansible playbooks → HashiCorp Vault

Transition guide for automation that today uses Ansible Vault files, plaintext `group_vars`, or GitLab CI variables for device passwords, enable secrets, and API tokens.

Use **HashiCorp Vault** as the secret store. Keep **Ansible Vault** only as a temporary bridge (or retire it) once lookups work.

Collection: [`community.hashi_vault`](https://docs.ansible.com/projects/ansible/latest/collections/community/hashi_vault/)

---

## Target pattern

```
Playbook / role
  → community.hashi_vault.vault_kv2_get (or hashi_vault) lookup
  → Vault (JWT from GitLab CI, or AppRole / token from controller/devcontainer)
  → ansible_* connection vars / modules (with no_log: true)
```

| Before | After |
|--------|--------|
| `group_vars/all/vault.yml` (Ansible Vault) | KV paths in HashiCorp Vault |
| `ansible_password` in CI variables | Lookup at runtime |
| Shared `vault_password_file` on runners | GitLab JWT → Vault (no Ansible vault password) |
| Secrets in inventory | Inventory = hosts only; creds from Vault |

---

## 1. Inventory what you use today

For each playbook repo, list:

- [ ] Ansible Vault encrypted files (`vault.yml`, `*vault*`)
- [ ] Plain vars with passwords / tokens
- [ ] GitLab masked variables consumed as `ansible_password`, `NETBOX_TOKEN`, etc.
- [ ] `ansible_connection` plugins that need `ansible_user` / `ansible_ssh_pass` / `ansible_become_password`
- [ ] Devcontainer or laptop `.env` files used when running playbooks locally

Map each secret to a Vault path using the project convention:

```
secret/network/{env}/{site}/{device}/credentials   # username, password, enable_secret
secret/platform/netbox                             # api_token
secret/platform/ansible/controller                 # optional shared automation user
```

---

## 2. Install collection & Python deps

On runners, controllers, and in Dev Containers:

```bash
ansible-galaxy collection install community.hashi_vault
pip install 'hvac>=1.2'   # required by the collection
```

Pin versions in `requirements.yml` / `requirements.txt` for reproducibility.

Example `requirements.yml`:

```yaml
collections:
  - name: community.hashi_vault
    version: ">=6.0.0"
```

---

## 3. Authentication by runtime

| Where Ansible runs | Vault auth | Notes |
|--------------------|------------|--------|
| **GitLab CI job** | JWT (`secrets:vault` *or* lookup with JWT) | Prefer GitLab → Vault JWT; see [GITLAB.md](GITLAB.md) |
| **Dedicated AWX / controller** | AppRole | Machine identity; rotate `secret_id` |
| **VS Code Dev Container** | Token or AppRole via `remoteEnv` | See [DEVCONTAINERS.md](DEVCONTAINERS.md) |
| **Engineer laptop (ad hoc)** | OIDC or short-lived token | Avoid long-lived personal tokens |

### Environment variables the collection honors

Common ones (see collection docs for full list):

- `VAULT_ADDR` / `ANSIBLE_HASHI_VAULT_ADDR`
- `VAULT_TOKEN` / `ANSIBLE_HASHI_VAULT_TOKEN`
- `ANSIBLE_HASHI_VAULT_AUTH_METHOD` (`token`, `approle`, `jwt`, …)
- `ANSIBLE_HASHI_VAULT_ROLE_ID` / `ANSIBLE_HASHI_VAULT_SECRET_ID` (AppRole)
- `ANSIBLE_HASHI_VAULT_JWT` (JWT string when not using token)

**Never** commit tokens, role secret IDs, or Ansible Vault passwords to git.

---

## 4. Replace Ansible Vault vars with lookups

### Before (Ansible Vault)

```yaml
# group_vars/all/vault.yml  (encrypted)
vault_ansible_user: netops
vault_ansible_password: "s3cret"
vault_enable: "enables3cret"
vault_netbox_token: "nbt_..."
```

```yaml
# playbook
vars:
  ansible_user: "{{ vault_ansible_user }}"
  ansible_ssh_pass: "{{ vault_ansible_password }}"
  ansible_become_password: "{{ vault_enable }}"
```

### After (HashiCorp Vault KV v2)

```yaml
# group_vars/all/vault_paths.yml  (plaintext — paths only)
vault_mount: secret
device_cred_path: "network/lab/dc1/{{ inventory_hostname }}/credentials"
netbox_secret_path: "platform/netbox"
```

```yaml
# playbooks/site.yml
- hosts: network
  gather_facts: false
  vars:
    _device_creds: "{{ lookup('community.hashi_vault.vault_kv2_get', device_cred_path, engine_mount_point=vault_mount) }}"
    ansible_user: "{{ _device_creds.secret.username }}"
    ansible_ssh_pass: "{{ _device_creds.secret.password }}"
    ansible_become_password: "{{ _device_creds.secret.enable_secret }}"
    ansible_become: true
    ansible_network_os: "{{ ansible_network_os | default('ios') }}"
  tasks:
    - name: Example — never print secrets
      ansible.builtin.debug:
        msg: "Logged in as {{ ansible_user }} (password redacted)"
      no_log: false   # ok — no secret in msg

    - name: Push config fragment
      cisco.ios.ios_config:
        lines:
          - "ntp server 10.0.0.1"
      no_log: true    # hide task args/results that might echo secrets
```

For a single field:

```yaml
netbox_token: "{{ lookup('community.hashi_vault.vault_kv2_get', 'platform/netbox', engine_mount_point='secret').secret.api_token }}"
```

Legacy-style path lookup (KV v2 URL form):

```yaml
# secret=mount/data/path  field on query string
password: "{{ lookup('community.hashi_vault.hashi_vault', 'secret=secret/data/network/lab/dc1/lab-rtr-01/credentials:password') }}"
```

Prefer `vault_kv2_get` for clarity with KV v2.

---

## 5. GitLab CI running Ansible

Two workable patterns:

### A. Inject files with `secrets:vault`, then run Ansible (simplest ops)

GitLab writes temp files; playbook reads env/file vars — no Vault plugin required in the job image.

```yaml
secrets:
  ANSIBLE_PASSWORD:
    vault: network/lab/dc1/lab-rtr-01/credentials/password@secret
    file: true
    token: $VAULT_ID_TOKEN
script:
  - ansible-playbook -i inventory playbooks/site.yml
```

Playbook uses `ansible_ssh_pass: "{{ lookup('file', lookup('env', 'ANSIBLE_PASSWORD')) }}"` when `file: true` (path in the variable).

### B. Ansible talks to Vault itself (better for many hosts)

Job authenticates once (JWT → token), exports `VAULT_TOKEN`, playbook uses lookups per host path.

```yaml
script:
  - export VAULT_ADDR="$VAULT_SERVER_URL"
  - export VAULT_TOKEN="$(vault write -field=token auth/jwt/login role=$VAULT_AUTH_ROLE jwt=$VAULT_ID_TOKEN)"
  - ansible-playbook -i inventory playbooks/site.yml
```

Use policy [`../policies/ansible-automation.hcl`](../policies/ansible-automation.hcl) (or reuse `gitlab-ci`).

See also [`../examples/ansible/`](../examples/ansible/).

---

## 6. Migration steps (per repo)

1. **Freeze** new secrets in Ansible Vault / CI variables.
2. **Write** equivalent secrets to HashiCorp Vault; verify with `vault kv get`.
3. **Add** `community.hashi_vault` to collection requirements; update CI image/devcontainer.
4. **Introduce** path vars (`vault_paths.yml`) alongside old `vault.yml`.
5. **Switch** one playbook (lab inventory only) to lookups; keep `no_log: true` on credential-sensitive tasks.
6. **Run** lab job from GitLab + once from Dev Container.
7. **Remove** Ansible Vault file and CI password variables after sign-off.
8. **Repeat** for stage/prod with stricter JWT roles / policies.

### Dual-run bridge (optional)

```yaml
ansible_ssh_pass: >-
  {{ lookup('community.hashi_vault.vault_kv2_get', device_cred_path, engine_mount_point='secret').secret.password
     | default(vault_ansible_password, true) }}
```

Remove the `default(...)` once Vault is mandatory.

---

## 7. Hardening checklist

- [ ] `no_log: true` on tasks that touch passwords / enable / tokens
- [ ] Disable or restrict `ANSIBLE_DEBUG` / verbose (`-vvv`) in prod pipelines
- [ ] Do not use `delegate_to: localhost` debug of secret vars
- [ ] Separate Vault policies: lab CI vs prod CI vs human AppRole
- [ ] Prefer SSH certs/OTP from Vault SSH engine over static `ansible_ssh_pass` when devices allow ([INSTALL.md](INSTALL.md) §8)
- [ ] Inventory and NetBox hold **paths**, not passwords ([NETBOX.md](NETBOX.md))

---

## 8. Acceptance criteria

- Lab playbook succeeds with **no** Ansible Vault password and **no** device password in GitLab variables
- Vault audit shows reads from the CI JWT / AppRole identity
- `git grep`-style review finds no plaintext prod passwords in the repo
- Same playbook runs in GitLab CI and in a Dev Container using Vault ([DEVCONTAINERS.md](DEVCONTAINERS.md))
