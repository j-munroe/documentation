#!/usr/bin/env bash
# Install tooling only — never curl secrets into the image here.
set -euo pipefail

if [[ -f requirements.yml ]]; then
  ansible-galaxy collection install -r requirements.yml
fi
if [[ -f requirements.txt ]]; then
  pip install --user -r requirements.txt
fi

if [[ -z "${VAULT_ADDR:-}" ]]; then
  echo "WARN: VAULT_ADDR is empty. On the host, export VAULT_ADDR and login before reopening the container." >&2
fi

if [[ -z "${VAULT_TOKEN:-}" && ! -f "${HOME}/.vault-token" ]]; then
  echo "WARN: No VAULT_TOKEN or ~/.vault-token. Ansible Vault lookups will fail until you authenticate." >&2
fi

echo "Dev container tooling ready."
