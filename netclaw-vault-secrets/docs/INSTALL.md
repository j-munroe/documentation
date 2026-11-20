# Install & bootstrap: HashiCorp Vault

This guide installs Vault for lab or first production footprint, then enables the engines used by GitLab, NetBox, and NetClaw.

Replace every `CHANGE_ME` / example hostname before use.

---

## 0. Prerequisites

- Linux host (Ubuntu 22.04/24.04 or RHEL 8/9 recommended)
- Outbound access to HashiCorp package repos **or** offline package mirror
- DNS name, e.g. `vault.example.local`
- TLS certificate + key (or lab self-signed for testing only)
- Ports: `8200/tcp` (API), `8201/tcp` (cluster, HA only)
- Firewall allow from: GitLab Runners, NetBox/Orb host, NetClaw host, admin jump hosts

Optional helper scripts live in [`../scripts/`](../scripts/).

---

## 1. Install Vault binary (Ubuntu example)

```bash
sudo apt-get update
sudo apt-get install -y wget gpg coreutils

wget -O- https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update
sudo apt-get install -y vault
vault version
```

**Container alternative (lab):**

```bash
docker volume create vault-data
docker run -d --name vault \
  -p 8200:8200 \
  -v vault-data:/vault/file \
  -e 'VAULT_LOCAL_CONFIG={"storage":{"file":{"path":"/vault/file"}},"listener":{"tcp":{"address":"0.0.0.0:8200","tls_disable":1}},"ui":true}' \
  --cap-add=IPC_LOCK \
  hashicorp/vault:1.18 server
```

> Lab-only: `tls_disable:1` is unacceptable for production. Use TLS as shown below.

---

## 2. Server configuration (production-shaped)

Create `/etc/vault.d/vault.hcl`:

```hcl
ui = true
disable_mlock = false

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-1"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/opt/vault/tls/vault.crt"
  tls_key_file  = "/opt/vault/tls/vault.key"
}

api_addr     = "https://vault.example.local:8200"
cluster_addr = "https://vault.example.local:8201"

# Optional telemetry later
```

Prepare directories:

```bash
sudo mkdir -p /opt/vault/data /opt/vault/tls /var/log/vault
sudo chown -R vault:vault /opt/vault /var/log/vault
# Install vault.crt / vault.key into /opt/vault/tls (mode 640, owner vault)
```

Enable and start:

```bash
sudo systemctl enable vault
sudo systemctl start vault
sudo systemctl status vault
```

---

## 3. Initialize, unseal, audit

```bash
export VAULT_ADDR="https://vault.example.local:8200"
# If using lab self-signed:
# export VAULT_SKIP_VERIFY=1

vault operator init -key-shares=5 -key-threshold=3 -format=json > /root/vault-init.json
# MOVE /root/vault-init.json to offline escrow IMMEDIATELY. Do not leave on disk.
```

Unseal (run 3 times with different key shares):

```bash
vault operator unseal
vault status
```

Login with root token once:

```bash
vault login
```

Enable audit:

```bash
vault audit enable file file_path=/var/log/vault/audit.log
```

Create an admin policy token for day-2 work, then **revoke root** or escrow it offline (see [SECURITY.md](SECURITY.md)).

---

## 4. Enable secrets engines

```bash
# KV v2 at secret/
vault secrets enable -path=secret kv-v2

# SSH engine
vault secrets enable -path=ssh ssh

# Optional PKI
# vault secrets enable -path=pki pki
# vault secrets tune -max-lease-ttl=8760h pki
```

Or run:

```bash
../scripts/02-enable-engines.sh
```

---

## 5. Path layout & sample secrets

Write lab samples (replace values):

```bash
vault kv put secret/platform/netbox \
  api_token="CHANGE_ME_NETBOX_TOKEN"

vault kv put secret/network/lab/dc1/lab-rtr-01/credentials \
  username="netops" \
  password="CHANGE_ME" \
  enable_secret="CHANGE_ME"

vault kv put secret/network/lab/shared/netclaw \
  username="netclaw" \
  password="CHANGE_ME"
```

Or:

```bash
../scripts/03-write-sample-secrets.sh
```

---

## 6. Policies

```bash
vault policy write netclaw-read   ../policies/netclaw-read.hcl
vault policy write gitlab-ci      ../policies/gitlab-ci.hcl
vault policy write netbox-agent   ../policies/netbox-agent.hcl
vault policy write netclaw-change ../policies/netclaw-change.hcl
```

---

## 7. Auth methods (summary)

### 7a. AppRole for NetClaw / services

```bash
vault auth enable approle

vault write auth/approle/role/netclaw \
  token_policies="netclaw-read" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=24h

vault read auth/approle/role/netclaw/role-id
vault write -f auth/approle/role/netclaw/secret-id
```

Or: `../scripts/04-configure-approle.sh`

Deliver `role_id` + `secret_id` to the NetClaw host via a secure channel (not Git).

### 7b. JWT for GitLab

Full steps: [GITLAB.md](GITLAB.md).

```bash
vault auth enable jwt

vault write auth/jwt/config \
  oidc_discovery_url="https://gitlab.example.local" \
  bound_issuer="https://gitlab.example.local"
```

---

## 8. SSH engine (pilot)

**OTP mode (fastest pilot):**

```bash
vault write ssh/roles/netclaw-troubleshoot \
  key_type=otp \
  default_user=netops \
  cidr_list=10.0.0.0/8
```

Install `vault-sshhelper` (or equivalent) on the target device/host so OTP is validated against Vault.

**CA mode (preferred long-term):**

```bash
vault write ssh/config/ca generate_signing_key=true
vault read -field=public_key ssh/config/ca > /tmp/vault-ssh-ca.pub
# Install as TrustedUserCAKeys on devices
vault write ssh/roles/netclaw-troubleshoot \
  key_type=ca \
  allow_user_certificates=true \
  allowed_users=netops \
  default_user=netops \
  ttl=30m \
  max_ttl=1h
```

---

## 9. Verify

```bash
vault status
vault secrets list
vault policy list
vault kv get secret/platform/netbox
vault audit list
```

From a Runner host / NetClaw host:

```bash
curl -sS --cacert /path/to/ca.crt "$VAULT_ADDR/v1/sys/health"
```

---

## 10. Next steps

1. [GITLAB.md](GITLAB.md) — wire CI JWT + `secrets:vault`
2. [NETBOX.md](NETBOX.md) — token in Vault + device path refs
3. [NETCLAW.md](NETCLAW.md) — Vault MCP registration
4. Return to [WORKPLAN.md](WORKPLAN.md) Phase 6–7 for SSH rollout and ops

---

## Rollback / break-glass

- If Vault is sealed: unseal with threshold key shares from escrow
- If Vault is down: automation must **fail closed** (no fallback to plaintext env files in prod)
- Emergency device access: offline break-glass credentials in a physical/enterprise PAM process — not in Git
