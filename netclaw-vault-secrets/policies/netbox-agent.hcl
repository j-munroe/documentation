# Orb / discovery agent
# vault policy write netbox-agent policies/netbox-agent.hcl

path "secret/data/network/*" {
  capabilities = ["read"]
}
path "secret/metadata/network/*" {
  capabilities = ["list", "read"]
}

# Tighten to lab-only in early rollout if preferred:
# path "secret/data/network/lab/*" { capabilities = ["read"] }
