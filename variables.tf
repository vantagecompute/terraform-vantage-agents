# ---- How to reach the node ---------------------------------------------------

variable "host" {
  description = "IP address or DNS name of the node that already runs Slurm."
  type        = string

  validation {
    condition     = length(var.host) > 0
    error_message = "host must not be empty."
  }
}

variable "ssh_user" {
  description = "SSH user on the node. It must be root or have passwordless sudo."
  type        = string

  validation {
    condition     = length(var.ssh_user) > 0
    error_message = "ssh_user must not be empty."
  }
}

variable "ssh_private_key" {
  description = "Contents of the SSH private key, for example file(\"~/.ssh/id_ed25519\"). It is the key itself, not a path."
  type        = string
  sensitive   = true
}

variable "ssh_port" {
  description = "SSH port of the node."
  type        = number
  default     = 22
}

# ---- Who the cluster is ------------------------------------------------------

variable "client_id" {
  description = "The cluster's Keycloak client ID, which is the cluster ID."
  type        = string

  validation {
    condition     = length(var.client_id) > 0 && !can(regex("[\\r\\n]", var.client_id))
    error_message = "client_id must be set and must not contain a line break."
  }
}

variable "client_secret" {
  description = "The cluster's Keycloak client secret."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.client_secret) > 0 && !can(regex("[\\r\\n]", var.client_secret))
    error_message = "client_secret must be set and must not contain a line break."
  }
}

variable "oidc_base_url" {
  description = "Keycloak base URL without /realms/vantage, for example https://auth.vantagecompute.ai."
  type        = string

  validation {
    condition     = can(regex("^https?://", var.oidc_base_url))
    error_message = "oidc_base_url must start with http:// or https://."
  }
}

variable "api_base_url" {
  description = "Base URL of the Vantage API the presence agent reports to, for example https://apis.vantagecompute.ai."
  type        = string

  validation {
    condition     = can(regex("^https?://", var.api_base_url))
    error_message = "api_base_url must start with http:// or https://."
  }
}

# ---- slurm-accounts-reconciler -----------------------------------------------

variable "ldap_url" {
  description = "LDAP URL of your Vantage organization."
  type        = string

  validation {
    condition     = length(var.ldap_url) > 0 && !can(regex("[\\r\\n]", var.ldap_url))
    error_message = "ldap_url must be set and must not contain a line break."
  }
}

variable "ldap_organization_id" {
  description = "Your Vantage organization ID."
  type        = string

  validation {
    condition     = length(var.ldap_organization_id) > 0 && !can(regex("[\\r\\n]", var.ldap_organization_id))
    error_message = "ldap_organization_id must be set and must not contain a line break."
  }
}

variable "ldap_bind_password" {
  description = "The LDAP bind password."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.ldap_bind_password) > 0 && !can(regex("[\\r\\n]", var.ldap_bind_password))
    error_message = "ldap_bind_password must be set and must not contain a line break."
  }
}

# ---- vref-agent --------------------------------------------------------------

variable "install_vref_agent" {
  description = "Install vref-agent. Turn it off until a vref-agent release with an on-cluster systemd-setup is published."
  type        = bool
  default     = true
}

variable "vref_api_url" {
  description = "Base URL of vref-api. Required when install_vref_agent is true."
  type        = string
  default     = ""

  validation {
    condition     = var.vref_api_url == "" || can(regex("^https?://", var.vref_api_url))
    error_message = "vref_api_url must start with http:// or https://."
  }
}

variable "vref_container_engine" {
  description = "pyxis or apptainer. Leave empty when the cluster runs neither."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "pyxis", "apptainer"], var.vref_container_engine)
    error_message = "vref_container_engine must be empty, pyxis or apptainer."
  }
}

variable "slurm_token_lifespan" {
  description = "Seconds a vref-agent Slurm token lives."
  type        = number
  default     = 604800
}

variable "slurm_token_refresh" {
  description = "A systemd OnCalendar value for re-minting the vref-agent Slurm token, such as daily."
  type        = string
  default     = "daily"

  validation {
    condition     = length(var.slurm_token_refresh) > 0 && !can(regex("[\\r\\n]", var.slurm_token_refresh))
    error_message = "slurm_token_refresh must be set and must not contain a line break."
  }
}

# ---- Presence agent ----------------------------------------------------------

variable "install_presence_agent" {
  description = "Install cluster-presence-agent, which makes the cluster show as Connected in Vantage."
  type        = bool
  default     = true
}

# ---- Where things come from --------------------------------------------------

variable "artifacts_url" {
  description = "Where the binaries are downloaded from."
  type        = string
  default     = "https://vantage-artifacts.vantagecompute.ai"
}

variable "release_track" {
  description = "The release line, MAJOR.MINOR, each binary follows: the newest release on it, so a 0.2 release never reaches a node on 0.1. A version variable below overrides it for one binary."
  type        = string
  default     = "0.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.release_track))
    error_message = "release_track must be a release line, MAJOR.MINOR, such as 0.1."
  }
}

variable "reconciler_version" {
  description = "slurm-accounts-reconciler version, or null to follow release_track. The track can move under you, and Terraform will not notice, so pin it in production."
  type        = string
  default     = null
}

variable "vref_agent_version" {
  description = "vref-agent version, or null to follow release_track. Pin it in production."
  type        = string
  default     = null
}

variable "presence_agent_version" {
  description = "cluster-presence-agent version, or null to follow release_track. Pin it in production."
  type        = string
  default     = null
}

variable "slurmrestd_url" {
  description = "The cluster's slurmrestd."
  type        = string
  default     = "http://127.0.0.1:6820"
}

variable "slurm_user" {
  description = "The user slurmctld runs as."
  type        = string
  default     = "slurm"
}
