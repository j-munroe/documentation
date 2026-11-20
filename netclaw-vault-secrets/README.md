# NetClaw Vault Secrets

Workplan and install setup for **HashiCorp Vault** as the secrets system of record for an agentic network-troubleshooting stack:

| Component | Role |
|-----------|------|
| **HashiCorp Vault** | Secrets vault (SSH creds, API tokens, short-lived certs) |
| **GitLab (on-prem)** | Source control + CI/CD JWT auth into Vault |
| **GitLab Runners** | Runtime that fetches secrets at job start |
| **NetBox Community** | Inventory / source of truth (paths & metadata, not passwords) |
| **NetClaw** | Agentic network engineer via Vault MCP |

## Why Vault

- Native GitLab `secrets:vault` + JWT/OIDC (no long-lived CI tokens)
- NetBox Discovery / Orb Agent can resolve Vault references
- NetClaw ships a first-class **HashiCorp Vault MCP** integration
- SSH secrets engine supports short-lived OTP / certificates for agents
- Works fully on-prem

## Docs

| Doc | Purpose |
|-----|---------|
| [WORKPLAN.md](docs/WORKPLAN.md) | Phased delivery plan, owners, acceptance criteria |
| [INSTALL.md](docs/INSTALL.md) | End-to-end install and bootstrap |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Trust boundaries and data flow |
| [GITLAB.md](docs/GITLAB.md) | JWT auth + Runner secret injection |
| [NETBOX.md](docs/NETBOX.md) | Inventory references, tokens, Orb Agent |
| [NETCLAW.md](docs/NETCLAW.md) | Vault MCP, policies, safe agent access |
| [SECURITY.md](docs/SECURITY.md) | Least privilege, audit, rotation |

## Quick start (lab)

```bash
# On a Linux host with Docker
cd scripts
./01-bootstrap-vault.sh
./02-enable-engines.sh
./03-write-sample-secrets.sh
./04-configure-approle.sh
```

Then wire GitLab JWT (see [GITLAB.md](docs/GITLAB.md)) and NetClaw MCP (see [NETCLAW.md](docs/NETCLAW.md)).

## Package layout

```
netclaw-vault-secrets/
├── README.md
├── docs/           # Workplan + install guides
├── policies/       # Example Vault HCL policies
├── scripts/        # Bootstrap helpers (lab/prod-shaped)
└── examples/       # GitLab CI, Orb Agent, NetClaw config snippets
```

## Promote to its own repository

This package currently lives under `j-munroe/documentation` because the Cursor GitHub App cannot create new personal repositories. To split it out:

1. Create an empty repo: https://github.com/new?name=netclaw-vault-secrets
2. Grant the **Cursor** GitHub App access to that repo (Settings → Applications), or select “All repositories” on the App install.
3. Reply in the agent chat asking to migrate this folder into `j-munroe/netclaw-vault-secrets`.

## Security note

Scripts and examples use **placeholders only**. Never commit real tokens, root tokens, unseal keys, or device passwords. Store production secrets in Vault; keep GitLab variables limited to Vault addressing and auth config.
