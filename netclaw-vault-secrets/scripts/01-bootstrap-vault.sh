#!/usr/bin/env bash
# Lab helper: start a local Vault dev/server-style container for experimentation.
# NOT for production. See docs/INSTALL.md for production install.
set -euo pipefail

NAME="${VAULT_CONTAINER_NAME:-vault-lab}"
PORT="${VAULT_LAB_PORT:-8200}"
IMAGE="${VAULT_IMAGE:-hashicorp/vault:1.18}"

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "Container $NAME already exists. Start with: docker start $NAME"
  exit 0
fi

docker volume create "${NAME}-data" >/dev/null

docker run -d --name "$NAME" \
  -p "${PORT}:8200" \
  --cap-add=IPC_LOCK \
  -e VAULT_DEV_ROOT_TOKEN_ID=root \
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
  "$IMAGE"

echo "Vault lab listening on http://127.0.0.1:${PORT}"
echo "export VAULT_ADDR=http://127.0.0.1:${PORT}"
echo "export VAULT_TOKEN=root"
echo "Next: ./02-enable-engines.sh"
