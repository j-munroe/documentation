# Ansible automation (CI controller or AppRole)
# vault policy write ansible-automation policies/ansible-automation.hcl

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

path "ssh/creds/netclaw-troubleshoot" {
  capabilities = ["create", "update"]
}
path "ssh/sign/netclaw-troubleshoot" {
  capabilities = ["create", "update"]
}
