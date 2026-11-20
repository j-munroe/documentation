#!/usr/bin/env bash
# Create AppRole for NetClaw (read policy). Prints role_id; secret_id once.
set -euo pipefail

: "${VAULT_ADDR:?Set VAULT_ADDR}"
: "${VAULT_TOKEN:?Set VAULT_TOKEN}"

ROLE="${NETCLAW_APPROLE_NAME:-netclaw}"
POLICY="${NETCLAW_POLICY:-netclaw-read}"

if ! vault auth list -format=json | grep -q '"approle/"'; then
  vault auth enable approle
fi

vault write "auth/approle/role/${ROLE}" \
  token_policies="${POLICY}" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=24h \
  bind_secret_id=true

echo "=== role_id (safe to store as non-secret config) ==="
vault read -field=role_id "auth/approle/role/${ROLE}/role-id"

echo "=== secret_id (treat as a secret; shown once) ==="
vault write -f -field=secret_id "auth/approle/role/${ROLE}/secret-id"

cat <<EOF

Configure NetClaw host:
  export VAULT_ADDR=${VAULT_ADDR}
  export VAULT_ROLE_ID=<role_id>
  export VAULT_SECRET_ID=<secret_id>
  export VAULT_TOKEN=\$(vault write -field=token auth/approle/login role_id=\$VAULT_ROLE_ID secret_id=\$VAULT_SECRET_ID)

See docs/NETCLAW.md for MCP registration.
EOF
