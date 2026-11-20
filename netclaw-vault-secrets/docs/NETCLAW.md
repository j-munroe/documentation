# NetClaw + HashiCorp Vault MCP

NetClaw integrates with the official Hashicorp **vault-mcp-server** so the agent can retrieve credentials and certificates without embedding secrets in skills or chat.

Upstream references:

- NetClaw Vault MCP spec: `specs/019-vault-mcp-server` in [automateyournetwork/netclaw](https://github.com/automateyournetwork/netclaw)
- Server: [hashicorp/vault-mcp-server](https://github.com/hashicorp/vault-mcp-server)

---

## 1. Security rules for agents

1. **Never** put device passwords in `SOUL.md`, skills, or git-tracked `.env`.
2. Secret **values must not appear** in chat, Canvas, or logs — inject into tools/files only.
3. Default policy = **read/troubleshoot**. Change/write uses a separate role + human approval (DefenseClaw).
4. Prefer SSH OTP/cert (TTL minutes) over static passwords.
5. All access must show up in Vault audit with the NetClaw AppRole identity.

---

## 2. Install vault-mcp-server

On the NetClaw host:

```bash
# Example: install binary from HashiCorp releases (pin a version in prod)
# go install github.com/hashicorp/vault-mcp-server@latest

command -v vault-mcp-server
```

---

## 3. Authenticate NetClaw to Vault

### Recommended: AppRole

On Vault (once):

```bash
# From scripts/04-configure-approle.sh or INSTALL.md §7a
vault read auth/approle/role/netclaw/role-id
vault write -f auth/approle/role/netclaw/secret-id
```

On NetClaw host, store in a **root-readable env file** outside git (e.g. `/etc/netclaw/vault.env`):

```bash
VAULT_ADDR=https://vault.example.local:8200
VAULT_ROLE_ID=CHANGE_ME
VAULT_SECRET_ID=CHANGE_ME
# Optional:
# VAULT_NAMESPACE=network-ops
```

Login helper (systemd `ExecStartPre` or wrapper):

```bash
export VAULT_TOKEN=$(vault write -field=token auth/approle/login \
  role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")
```

> The MCP server commonly expects `VAULT_TOKEN`. Refresh the token on a schedule shorter than `token_ttl`.

### Lab-only: static token

```bash
VAULT_ADDR=https://vault.example.local:8200
VAULT_TOKEN=hvs.CHANGE_ME
```

Do not use root tokens.

---

## 4. Register MCP in OpenClaw / NetClaw config

Example fragment (see [`../examples/openclaw-vault.json`](../examples/openclaw-vault.json)):

```json
{
  "mcpServers": {
    "vault-mcp": {
      "command": "vault-mcp-server",
      "args": [],
      "env": {
        "VAULT_ADDR": "${VAULT_ADDR}",
        "VAULT_TOKEN": "${VAULT_TOKEN}"
      }
    }
  }
}
```

Restart the NetClaw / OpenClaw gateway after registration.

---

## 5. Policies

Attach `netclaw-read` by default:

- Read `secret/data/network/lab/**` and platform tokens needed for inventory
- List metadata
- Issue SSH creds for troubleshoot role only

Use `netclaw-change` only when:

- DefenseClaw / approval gate allows a change window
- Separate AppRole or temporary token elevation is issued

Policy files: [`../policies/`](../policies/).

---

## 6. Operational prompts (safe)

Good:

- “List secrets under `secret/network/lab` (names only).”
- “Resolve `lab-rtr-01` from NetBox, fetch Vault creds, run a show interface summary.”

Bad:

- “Print the password for lab-rtr-01.”
- “Dump all prod credentials.”

If the model attempts to display a secret, skills/MCP should redact; treat visible secrets as an incident.

---

## 7. Validation checklist

- [ ] `vault-mcp` appears in MCP server list
- [ ] List paths works; values redacted
- [ ] Lab device login via injected creds succeeds
- [ ] Vault audit log shows AppRole / policy name
- [ ] Prod paths denied under `netclaw-read`
- [ ] Write/change requires approval path

---

## 8. Transition from `.env` device passwords

NetClaw `.env.example` includes `NETCLAW_USERNAME` / `NETCLAW_PASSWORD` for quick labs. For your on-prem path:

1. Keep lab `.env` only on disposable labs.
2. Point skills/testbeds at Vault-backed injection.
3. Remove static passwords from host env once Phase 5 acceptance passes ([WORKPLAN.md](WORKPLAN.md)).
