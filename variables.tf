variable "ssh_user" {
  description = "SSH username for the target host"
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key for authentication"
  type        = string
  sensitive   = true
}

variable "host" {
  description = "Target host IP or DNS"
  type        = string
}

variable "oidc_client_id" {
  description = "OIDC client ID for both agents"
  type        = string
}

variable "oidc_client_secret" {
  description = "OIDC client secret for both agents"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Cluster name for vantage-agent"
  type        = string
}

variable "install_type" {
  description = "Installation type: 'snap' (default) or 'pypi'"
  type        = string
  default     = "snap"
}
