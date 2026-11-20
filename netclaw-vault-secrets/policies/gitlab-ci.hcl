# GitLab CI JWT role — lab automation
# vault policy write gitlab-ci policies/gitlab-ci.hcl

path "secret/data/network/lab/*" {
  capabilities = ["read"]
}
path "secret/metadata/network/lab/*" {
  capabilities = ["list", "read"]
}

path "secret/data/platform/netbox" {
  capabilities = ["read"]
}
path "secret/metadata/platform/netbox" {
  capabilities = ["read"]
}

# Optional: allow CI to request SSH OTP for lab jumps
path "ssh/creds/netclaw-troubleshoot" {
  capabilities = ["create", "update"]
}
