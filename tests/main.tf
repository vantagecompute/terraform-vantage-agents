# Applies the module against the stub CDN on a throwaway VM. Test use only.
# Set TF_VAR_host, TF_VAR_ssh_port, TF_VAR_ssh_user and TF_VAR_ssh_private_key.
variable "host" { type = string }
variable "ssh_port" { type = number }
variable "ssh_user" { type = string }
variable "ssh_private_key" {
  type      = string
  sensitive = true
}

# null follows the module's release_track.
variable "reconciler_version" {
  type    = string
  default = null
}

module "agents" {
  source = "../"

  host            = var.host
  ssh_port        = var.ssh_port
  ssh_user        = var.ssh_user
  ssh_private_key = var.ssh_private_key

  client_id            = "test-cluster"
  client_secret        = "a \"quoted\" \\ it's secret"
  oidc_base_url        = "http://127.0.0.1:8099"
  artifacts_url        = "http://127.0.0.1:8099"
  api_base_url         = "https://api.example.test"
  ldap_url             = "ldaps://ldap.example.test"
  ldap_organization_id = "org-123"
  ldap_bind_password   = "bind-password"
  vref_api_url         = "https://vref.example.test"
  reconciler_version   = var.reconciler_version
}
