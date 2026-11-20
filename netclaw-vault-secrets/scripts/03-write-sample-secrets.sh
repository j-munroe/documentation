#!/usr/bin/env bash
# Write placeholder secrets for lab validation. Replace CHANGE_ME values.
set -euo pipefail

: "${VAULT_ADDR:?Set VAULT_ADDR}"
: "${VAULT_TOKEN:?Set VAULT_TOKEN}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

vault kv put secret/platform/netbox \
  api_token="CHANGE_ME_NETBOX_TOKEN" \
  url="https://netbox.example.local"

vault kv put secret/network/lab/dc1/lab-rtr-01/credentials \
  username="netops" \
  password="CHANGE_ME" \
  enable_secret="CHANGE_ME"

vault kv put secret/network/lab/shared/netclaw \
  username="netclaw" \
  password="CHANGE_ME"

# Load policies if present
for p in netclaw-read gitlab-ci netbox-agent netclaw-change ansible-automation; do
  f="$ROOT/policies/${p}.hcl"
  if [[ -f "$f" ]]; then
    vault policy write "$p" "$f"
    echo "Wrote policy $p"
  fi
done

echo "Sample secrets written under secret/platform/netbox and secret/network/lab/..."
echo "Replace CHANGE_ME values before any real device use."
echo "Next: ./04-configure-approle.sh"
