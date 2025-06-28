
# terraform-vantage-agents

Terraform module to automate the installation and configuration of both **vantage-agent** and **jobbergate-agent** on a remote Linux host. Supports installation via **Snap** (default) or **PyPI** (virtualenv + systemd), with all configuration handled for you.

---

## Features

- Installs and configures both `vantage-agent` and `jobbergate-agent` on a remote host via SSH
- Supports two installation methods:
  - **Snap** (default): Installs agents as snaps, manages snapd, and configures via snap set
  - **PyPI**: Installs agents in Python virtual environments, configures via environment files, and manages with systemd
- Handles all required configuration, secrets, and service management

---

## Usage

Import the module directly from GitHub:

```hcl
module "vantage_agents" {
  source = "github.com/vantagecompute/terraform-vantage-agents"

  ssh_user         = var.ssh_user
  ssh_private_key  = file(var.ssh_private_key)
  host             = var.host

  oidc_client_id     = var.oidc_client_id   # Vantage cluster client-id
  oidc_client_secret = var.oidc_client_secret   # Vantage cluster client-secret
  cluster_name       = var.cluster_name

  # Optional: set to "pypi" to use PyPI/venv/systemd instead of Snap
  # install_type = "pypi"
}
```

---

## Variables

| Name                | Type   | Description                                                      | Required |
|---------------------|--------|------------------------------------------------------------------|----------|
| `ssh_user`          | string | SSH username for remote host                                     | yes      |
| `ssh_private_key`   | string | Path to SSH private key file (use `file()` to load contents)     | yes      |
| `host`              | string | Hostname or IP address of the remote host                        | yes      |
| `oidc_client_id`    | string | OIDC client ID for Vantage cluster                               | yes      |
| `oidc_client_secret`| string | OIDC client secret for Vantage cluster                           | yes      |
| `cluster_name`      | string | Name of the Vantage cluster                                      | yes      |
| `install_type`      | string | Installation type: `snap` (default) or `pypi`                    | no       |

---

## Installation Methods

### Snap (default)
- Installs `snapd` and both agents as snaps
- Configures agents using `snap set`
- Enables and starts snap-managed systemd services

### PyPI
- Installs Python 3, pip, and venv
- Creates isolated virtual environments for each agent
- Installs agents from PyPI
- Deploys environment files and systemd unit files for each agent
- Enables and starts systemd services

---

## Notes

- The remote host must be accessible via SSH and support `sudo`.
- For Snap installs, the host must support snapd (typically Ubuntu/Debian).
- For PyPI installs, the host must support Python 3 and systemd.
- All secrets are transferred securely via SSH.

---

## License

Apache 2.0
