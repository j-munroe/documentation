# NetBox custom fields (suggested)

Add on **Device** (or Device Role) in NetBox Community:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `vault_path` | Text | No | KV path without mount, e.g. `network/lab/dc1/lab-rtr-01/credentials` |
| `vault_ssh_role` | Text | No | e.g. `netclaw-troubleshoot` |
| `credential_env` | Selection (`lab`,`stage`,`prod`) | No | Environment segment for path templates |

## Example device

- Name: `lab-rtr-01`
- Site: `dc1`
- `vault_path`: `network/lab/dc1/lab-rtr-01/credentials`
- `vault_ssh_role`: `netclaw-troubleshoot`

Vault object:

```bash
vault kv put secret/network/lab/dc1/lab-rtr-01/credentials \
  username=netops password=... enable_secret=...
```
