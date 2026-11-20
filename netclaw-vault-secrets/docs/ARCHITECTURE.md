# Architecture

## Trust boundaries

| Zone | Components | Secrets access |
|------|------------|----------------|
| **Secrets core** | Vault cluster, unseal operators, audit storage | All mounts (admin only) |
| **CI** | GitLab, GitLab Runners | JWT → role-scoped KV paths |
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

## Data flow (CI)

```
GitLab job (protected branch)
  → id_tokens JWT
  → Vault auth/jwt
  → secrets:vault → temp files in job
  → Ansible / scripts
  → devices / APIs
```

## What lives where

| Data | Store |
|------|-------|
| Device hostname, role, site, IP, platform | **NetBox** |
| Vault path / credential role name | **NetBox** custom field or naming convention |
| Username / password / enable / API tokens | **Vault KV** |
| Short-lived SSH | **Vault SSH engine** |
| Automation code | **GitLab** |
| Agent skills / MCP config | **NetClaw host** (no secret values in git) |

## Auth method map

| Client | Auth | Policy |
|--------|------|--------|
| Human admins | OIDC or userpass + MFA (optional) | admin / ops |
| GitLab CI | JWT | `gitlab-ci` (env-scoped) |
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
