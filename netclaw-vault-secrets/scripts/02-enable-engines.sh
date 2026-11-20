#!/usr/bin/env bash
# Enable KV v2 + SSH engines. Requires VAULT_ADDR and a token with sudo/root.
set -euo pipefail

: "${VAULT_ADDR:?Set VAULT_ADDR}"
: "${VAULT_TOKEN:?Set VAULT_TOKEN}"

if ! command -v vault >/dev/null 2>&1; then
  echo "vault CLI not found in PATH" >&2
  exit 1
fi

if ! vault secrets list -format=json | grep -q '"secret/"'; then
  vault secrets enable -path=secret kv-v2
  echo "Enabled KV v2 at secret/"
else
  echo "secret/ already mounted"
fi

if ! vault secrets list -format=json | grep -q '"ssh/"'; then
  vault secrets enable -path=ssh ssh
  echo "Enabled SSH engine at ssh/"
else
  echo "ssh/ already mounted"
fi

vault write ssh/roles/netclaw-troubleshoot \
  key_type=otp \
  default_user=netops \
  cidr_list="${SSH_CIDR_LIST:-10.0.0.0/8}" \
  >/dev/null

echo "Configured ssh/roles/netclaw-troubleshoot (OTP). Adjust cidr_list for your network."
echo "Next: ./03-write-sample-secrets.sh"
