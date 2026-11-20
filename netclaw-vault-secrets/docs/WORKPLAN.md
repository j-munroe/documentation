# Workplan: HashiCorp Vault for NetClaw + GitLab + NetBox

## Goal

Replace static GitLab CI variables, Ansible Vault files, Dev Container `.env` secrets, and other ad-hoc credential stores with **HashiCorp Vault** as the single secrets system of record for network troubleshooting automation and NetClaw agents.

## Current state (baseline)

- GitLab on-prem + GitLab Runners
- Ansible playbooks (often Ansible Vault and/or CI-injected passwords)
- VS Code Dev Containers that need the same secrets locally
- NetBox Community (inventory SoT)
- Credentials likely in CI variables, local files, or device shared accounts
- Target: NetClaw for advanced agentic troubleshooting

## Target state

```
                 ┌─────────────────┐
                 │  HashiCorp Vault │
                 │  (secrets SoT)   │
                 └────────┬────────┘
      ┌───────────┬───────┼───────┬───────────┐
      │           │       │       │           │
 GitLab JWT  Ansible   Dev Cont. NetClaw   Orb/NetBox
 (CI jobs)   lookups   remoteEnv AppRole   (discovery)
      │           │       │       │           │
      └───────────┴───────┼───────┴───────────┘
                          ▼
                   Devices / APIs
```

**Rules**

1. Vault holds secrets; NetBox holds inventory + optional Vault *path* references.
2. Prefer short-lived SSH certs/OTP over static passwords for agents.
3. Separate **read/troubleshoot** vs **change/write** Vault policies.
4. Every secret read is audited.
5. Same Vault **paths** for CI Ansible and Dev Container Ansible; different **auth** identities.

---

## Phase 0 — Decisions & prerequisites

**Outcomes**

- [ ] Choose Vault edition: **OSS** (start here) or Enterprise (namespaces, replication)
- [ ] Choose HA: single node (lab) vs Raft/Consul (prod)
- [ ] Choose auth methods: **JWT** (GitLab), **AppRole** (NetClaw/Ansible controllers), **OIDC** (humans / Dev Containers)
- [ ] Confirm TLS: internal CA or public cert for `VAULT_ADDR`
- [ ] Confirm network path: Runners, NetBox host, NetClaw host → Vault:8200

**Acceptance**

- Written architecture sign-off (see [ARCHITECTURE.md](ARCHITECTURE.md))
- Host sizing: 2 vCPU / 4 GB RAM minimum for lab; prod per HashiCorp guidance + disk for audit logs

---

## Phase 1 — Vault install & harden

**Tasks**

- [ ] Install Vault (package or container) on dedicated host/VM
- [ ] Enable TLS listener
- [ ] Initialize + unseal (store keys in break-glass procedure, not Git)
- [ ] Enable audit device (`file` or `socket`)
- [ ] Disable root token for day-2 ops; create admin identity

**Acceptance**

- `vault status` shows sealed=false, HA healthy (if clustered)
- Audit log receives a test read
- Root token revoked or escrowed offline

**Guide:** [INSTALL.md](INSTALL.md) §1–3

---

## Phase 2 — Secrets engines & path design

**Mounts**

| Mount | Engine | Purpose |
|-------|--------|---------|
| `secret/` | KV v2 | Static device creds, API tokens, enable secrets |
| `ssh/` | SSH | Short-lived OTP or signed SSH certs |
| `pki/` (optional) | PKI | Device/client certs for gNMI/TLS |

**Path convention**

```
secret/data/network/{env}/{site}/{device}/credentials
secret/data/platform/netbox/api_token
secret/data/platform/gitlab/runner_helpers   # if needed
ssh/roles/netclaw-troubleshoot
ssh/roles/netclaw-change
```

**Envs:** `lab`, `stage`, `prod`

**Acceptance**

- Sample secrets written for one lab device + NetBox token
- Policies in `policies/` applied and tested with a non-root token

**Guide:** [INSTALL.md](INSTALL.md) §4–5 · [SECURITY.md](SECURITY.md)

---

## Phase 3 — GitLab + Runners

**Tasks**

- [ ] Configure Vault JWT auth for GitLab issuer
- [ ] Bound claims: project path, protected branches, environment
- [ ] Example `.gitlab-ci.yml` with `id_tokens` + `secrets:vault`
- [ ] Migrate one pipeline off CI-stored passwords
- [ ] Ensure MR pipelines cannot read `prod/` paths

**Acceptance**

- Protected-branch job reads `secret/network/lab/...` successfully
- Unprotected/MR job denied for `prod/`
- No device password visible in job logs

**Guide:** [GITLAB.md](GITLAB.md)

---

## Phase 3b — Ansible playbooks

**Tasks**

- [ ] Inventory Ansible Vault files, plaintext creds, and CI password variables per repo
- [ ] Install `community.hashi_vault` (+ `hvac`) in CI images and Dev Containers
- [ ] Introduce plaintext `vault_paths.yml`; switch one lab playbook to `vault_kv2_get`
- [ ] Wire GitLab JWT → `VAULT_TOKEN` (or `secrets:vault` files) for Ansible jobs
- [ ] Apply `no_log: true` on credential-sensitive tasks; remove Ansible Vault after lab sign-off

**Acceptance**

- Lab playbook runs in CI with **no** Ansible Vault password and **no** device password CI variables
- Vault audit shows JWT/AppRole identity on secret reads

**Guide:** [ANSIBLE.md](ANSIBLE.md) · examples in `examples/ansible/`

---

## Phase 3c — VS Code Dev Containers

**Tasks**

- [ ] Strip secrets from `.env`, Dockerfile, and `devcontainer.json`
- [ ] Pass `VAULT_ADDR` / `VAULT_TOKEN` via `remoteEnv` + optional `~/.vault-token` mount
- [ ] Document host `vault login` (OIDC) before “Reopen in Container”
- [ ] Smoke-test: same lab playbook as CI, using engineer identity (not CI JWT)

**Acceptance**

- Container rebuild works with empty git tree for secrets
- Missing token fails closed (no plaintext fallback)
- Audit distinguishes human/dev AppRole from CI JWT

**Guide:** [DEVCONTAINERS.md](DEVCONTAINERS.md) · examples in `examples/devcontainer/`

---

## Phase 4 — NetBox Community

**Tasks**

- [ ] Create dedicated NetBox API token (least privilege); store in Vault
- [ ] Add custom field or tag convention for `vault_path` on devices/roles
- [ ] (Optional) Configure Orb Agent / discovery `secrets_manager: vault`
- [ ] Document: NetBox UI never stores plaintext device passwords

**Acceptance**

- Automation resolves device → Vault path → credential without NetBox holding the secret
- NetBox token rotatable without code changes

**Guide:** [NETBOX.md](NETBOX.md)

---

## Phase 5 — NetClaw integration

**Tasks**

- [ ] Install/register HashiCorp `vault-mcp-server`
- [ ] Auth NetClaw with **AppRole** (preferred) or short-lived token
- [ ] Apply `policies/netclaw-read.hcl` (and separate change policy)
- [ ] Configure `VAULT_ADDR` / role-id / secret-id injection (not long-lived root)
- [ ] Verify secrets are **injected**, never echoed in chat/logs
- [ ] Wire DefenseClaw / approval gates for write + change-role use

**Acceptance**

- NetClaw can list secret *paths* and connect to one lab device using Vault-sourced creds
- Chat/UI shows redacted values only
- Vault audit shows agent identity on each read

**Guide:** [NETCLAW.md](NETCLAW.md)

---

## Phase 6 — SSH modernization (recommended)

**Tasks**

- [ ] Enable SSH secrets engine (OTP and/or CA mode)
- [ ] Deploy CA public key or `vault-sshhelper` on pilot devices
- [ ] NetClaw / runners request short-lived creds per session
- [ ] Retire shared static passwords where possible

**Acceptance**

- Lab device login works with Vault-issued OTP/cert; TTL ≤ 30 minutes
- Static password path marked deprecated

---

## Phase 7 — Operate & harden

**Tasks**

- [ ] Rotation runbook (NetBox token, AppRole secret-id, device creds)
- [ ] Alert on Vault seal, audit disk full, auth failures
- [ ] Backup Raft/snapshots + restore drill
- [ ] Quarterly policy review (prod change role membership)

**Acceptance**

- Documented RTO for Vault restore
- Successful restore drill recorded

---

## Suggested order of execution

| Order | Phase | Depends on |
|------:|-------|------------|
| 1 | 0 Decisions | — |
| 2 | 1 Install | 0 |
| 3 | 2 Engines/paths | 1 |
| 4 | 3 GitLab | 2 |
| 5 | 3b Ansible | 2–3 |
| 6 | 3c Dev Containers | 2 (+ 3b for shared playbooks) |
| 7 | 4 NetBox | 2 |
| 8 | 5 NetClaw | 2 (+ ideally 4) |
| 9 | 6 SSH engine | 5 |
| 10 | 7 Operate | 3–6 |

Phases 3 / 3b / 4 can overlap after Phase 2. Do 3c once lab Vault paths exist so local and CI stay aligned.

---

## Out of scope (for later)

- CyberArk / enterprise PAM session recording (if mandated, put in front of human break-glass; keep Vault for automation)
- Multi-datacenter Vault Enterprise replication
- Full device fleet CA rollout (pilot first)

---

## Success metrics

- Zero production device passwords in GitLab CI variables
- Zero Ansible Vault / committed `.env` passwords required for lab (then prod) playbooks
- Dev Containers run the same playbooks using Vault auth (no secrets in the image)
- 100% of NetClaw device access audited in Vault
- Separate policies for troubleshoot vs change
- Time-to-rotate NetBox API token &lt; 15 minutes (procedure only; no code deploy)
