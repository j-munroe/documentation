# NetClaw default: troubleshoot / read-only
# vault policy write netclaw-read policies/netclaw-read.hcl

# Lab network device credentials
path "secret/data/network/lab/*" {
  capabilities = ["read"]
}
path "secret/metadata/network/lab/*" {
  capabilities = ["list", "read"]
}

# Shared lab identity used by agent testbeds (optional)
path "secret/data/network/lab/shared/*" {
  capabilities = ["read"]
}
path "secret/metadata/network/lab/shared/*" {
  capabilities = ["list", "read"]
}

# Platform tokens needed for inventory lookups
path "secret/data/platform/netbox" {
  capabilities = ["read"]
}
path "secret/metadata/platform/netbox" {
  capabilities = ["read"]
}

# SSH OTP / sign for troubleshoot role only
path "ssh/creds/netclaw-troubleshoot" {
  capabilities = ["create", "update"]
}
path "ssh/sign/netclaw-troubleshoot" {
  capabilities = ["create", "update"]
}

# Discovery
path "sys/mounts" {
  capabilities = ["read"]
}
