# Architecture

## Trust boundaries

| Zone | Components | Secrets access |
|------|------------|----------------|
| **Secrets core** | Vault cluster, unseal operators, audit storage | All mounts (admin only) |
| **CI** | GitLab, GitLab Runners, Ansible in CI | JWT → role-scoped KV paths |
| **Workstation** | VS Code Dev Containers, local Ansible | OIDC/token/AppRole via host → `remoteEnv` |
| **Inventory** | NetBox Community, optional Orb Agent | Token in Vault; device *paths* in NetBox |
| **Agent** | NetClaw + Vault MCP + DefenseClaw | AppRole → read (default); change role gated |
| **Network devices** | Routers/switches/firewalls | Accept SSH cert/OTP or static user from Vault |

## Data flow (troubleshoot)

```
Engineer → NetClaw chat
        → skill needs device access
        → Vault MCP (AppRole, netclaw-read)
        → KV read OR ssh/creds
        → pyATS / SSH / gNMI (secret injected, not printed)
        → device
        → evidence returned to chat (no secrets)
```

## Data flow (CI / Ansible)

```
GitLab job (protected branch)
  → id_tokens JWT
  → Vault auth/jwt
  → VAULT_TOKEN or secrets:vault files
  → Ansible community.hashi_vault lookups
  → devices / APIs
```

## Data flow (Dev Container)

```
Engineer → vault login (OIDC) on host
        → VAULT_TOKEN / ~/.vault-token
        → Dev Container remoteEnv / mount
        → same Ansible playbooks / scripts
        → Vault audit records human identity
```

## What lives where

| Data | Store |
|------|-------|
| Device hostname, role, site, IP, platform | **NetBox** |
| Vault path / credential role name | **NetBox** custom field or naming convention |
| Username / password / enable / API tokens | **Vault KV** |
| Short-lived SSH | **Vault SSH engine** |
| Automation code / Dev Container definition | **GitLab** (no secret values) |
| Agent skills / MCP config | **NetClaw host** (no secret values in git) |

## Auth method map

| Client | Auth | Policy |
|--------|------|--------|
| Human admins / Dev Containers | OIDC or short-lived token | lab read / ops |
| GitLab CI / Ansible in CI | JWT | `gitlab-ci` or `ansible-automation` |
| Ansible controller (non-CI) | AppRole | `ansible-automation` |
| NetClaw | AppRole | `netclaw-read` / `netclaw-change` |
| Orb / discovery | AppRole or token | `netbox-agent` |

## Failure modes

| Failure | Expected behavior |
|---------|-------------------|
| Vault sealed / down | Jobs and NetClaw fail closed |
| Wrong GitLab branch | JWT role denies `prod/` |
| NetClaw asks for secret display | MCP/skill redacts; inject to file/tool only |
| Compromised AppRole secret-id | Rotate secret-id; audit prior reads |

## Network diagram (logical)

```
[GitLab] ----JWT----\
[Runners] -----------\---- HTTPS :8200 ---- [Vault]
[NetClaw] --AppRole--/
[NetBox/Orb] --token-/
        \
         \---- inventory API (no passwords)
```
