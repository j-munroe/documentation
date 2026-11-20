# GitLab on-prem + Vault

Wire GitLab CI/CD so jobs authenticate with **JWT ID tokens** and pull secrets via `secrets:vault`. Do not store device passwords in GitLab CI/CD variables.

Official reference: [Use HashiCorp Vault secrets in GitLab CI/CD](https://docs.gitlab.com/ci/secrets/hashicorp_vault/).

---

## 1. Vault JWT auth

```bash
export VAULT_ADDR="https://vault.example.local:8200"
vault auth enable jwt

# GitLab external URL is the issuer / discovery base
vault write auth/jwt/config \
  oidc_discovery_url="https://gitlab.example.local" \
  bound_issuer="https://gitlab.example.local"
```

If your GitLab uses a custom CA, ensure Vault trusts it (`VAULT_CACERT` on the Vault server for outbound discovery, or use `jwks_url` explicitly).

---

## 2. Role for network automation project

Example: allow `lab` reads from project `network/automation` on protected branches.

```bash
vault write auth/jwt/role/gitlab-network-lab \
  role_type="jwt" \
  user_claim="user_email" \
  bound_audiences="https://vault.example.local" \
  bound_claims_type="glob" \
  bound_claims='{
    "project_path": "network/automation",
    "ref_protected": "true"
  }' \
  claim_mappings='{"project_path":"project_path","ref":"ref"}' \
  token_policies="gitlab-ci" \
  token_ttl="15m"
```

Create a stricter role for production (separate policy limited to `secret/data/network/prod/...`).

---

## 3. GitLab CI variables (non-secret)

Set at group or project level (not masked secrets of device passwords):

| Variable | Example | Protected |
|----------|---------|-----------|
| `VAULT_SERVER_URL` | `https://vault.example.local:8200` | Yes |
| `VAULT_AUTH_PATH` | `jwt` | Optional |
| `VAULT_AUTH_ROLE` | `gitlab-network-lab` | Yes |

Optional: `VAULT_CACERT` as a **File** variable containing your CA PEM.

---

## 4. Example job

See also [`../examples/gitlab-ci.yml`](../examples/gitlab-ci.yml).

```yaml
stages:
  - troubleshoot

variables:
  VAULT_SERVER_URL: "https://vault.example.local:8200"
  VAULT_AUTH_ROLE: "gitlab-network-lab"

read_lab_creds:
  stage: troubleshoot
  id_tokens:
    VAULT_ID_TOKEN:
      aud: https://vault.example.local
  secrets:
    NETBOX_TOKEN:
      vault: platform/netbox/api_token@secret
      file: false
      token: $VAULT_ID_TOKEN
    DEVICE_PASSWORD:
      vault: network/lab/dc1/lab-rtr-01/credentials/password@secret
      file: true
      token: $VAULT_ID_TOKEN
  script:
    - 'echo "NetBox token length: ${#NETBOX_TOKEN}"'
    - 'test -n "$DEVICE_PASSWORD" && echo "device password file present"'
    # Use $DEVICE_PASSWORD as a file path when file: true
  rules:
    - if: '$CI_COMMIT_REF_PROTECTED == "true"'
```

Notes:

- Default engine is **KV v2**. Path `platform/netbox/api_token@secret` → `secret/data/platform/netbox` field `api_token`.
- Prefer `file: true` for passwords so they are less likely to leak via shell tracing.
- Never `echo` secret values.

---

## 5. Runner requirements

- GitHub-compatible: GitLab Runner with secrets support (modern Runner versions)
- Runner network path to Vault:8200
- If Docker executor: mount CA or use `VAULT_CACERT`
- Use **protected runners** for production roles when possible

---

## 6. Migration checklist

- [ ] Inventory all CI variables that hold passwords/tokens
- [ ] Write each into Vault under the path convention
- [ ] Switch one job to `secrets:vault`
- [ ] Remove plaintext variable from GitLab after validation
- [ ] Repeat per environment (`lab` → `stage` → `prod`)

---

## 7. Troubleshooting

| Symptom | Check |
|---------|-------|
| `error authenticating to vault` | Issuer URL, `aud` claim, JWKS reachability from Vault |
| `permission denied` | Policy paths vs KV v2 (`secret/data/...` + `secret/metadata/...`) |
| Works on main, fails on MR | `ref_protected` / bound claims — expected for prod |
| Empty secret | Field name mismatch; confirm with `vault kv get` |
