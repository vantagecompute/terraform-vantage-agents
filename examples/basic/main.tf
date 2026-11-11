variable "ssh_private_key_file" {
  type    = string
  default = "~/.ssh/id_ed25519"
}
variable "client_secret" {
  type      = string
  sensitive = true
}
variable "ldap_bind_password" {
  type      = string
  sensitive = true
}

module "vantage_agents" {
  source = "../.."

  host            = "10.0.0.5"
  ssh_user        = "ubuntu"
  ssh_private_key = file(pathexpand(var.ssh_private_key_file))

  client_id     = "my-cluster-id"
  client_secret = var.client_secret
  oidc_base_url = "https://auth.vantagecompute.ai"
  api_base_url  = "https://apis.vantagecompute.ai"

  ldap_url             = "ldaps://ldap.vantagecompute.ai"
  ldap_organization_id = "my-organization-id"
  ldap_bind_password   = var.ldap_bind_password

  vref_api_url = "https://vref.example.com"

}
