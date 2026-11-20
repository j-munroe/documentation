# NetClaw elevated: change windows only (pair with approval gates)
# vault policy write netclaw-change policies/netclaw-change.hcl

# Lab credentials: read + rotate during approved changes
path "secret/data/network/lab/*" {
  capabilities = ["read", "create", "update"]
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

# Change-oriented SSH role (separate from troubleshoot)
path "ssh/creds/netclaw-change" {
  capabilities = ["create", "update"]
}
path "ssh/sign/netclaw-change" {
  capabilities = ["create", "update"]
}

# Explicitly no prod in this example — add a dedicated prod-change policy later
