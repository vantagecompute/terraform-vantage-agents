# Vantage & Jobbergate Agent Terraform Example (`vantage_agents`)

This example demonstrates how to install `vantage-agent` and `jobbergate-agent` on a remote host using either Snap (default) or PyPI, controlled by the `install_type` variable.

## Usage

Set `install_type` to `snap` (default) or `pypi` to control the installation method.

```hcl
module "vantage_agents" {
  source = "../../modules/vantage_agents"

  ssh_user        = var.ssh_user
  ssh_private_key = var.ssh_private_key
  host            = var.host

  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret
  cluster_name       = var.cluster_name
  install_type       = var.install_type
}
```

## Variables
- `install_type`: `snap` (default) or `pypi`
- `oidc_client_id`, `oidc_client_secret`, `cluster_name`, `ssh_user`, `ssh_private_key`, `host`

## Notes
- For `snap`, the module installs snapd and configures the agents as snaps.
- For `pypi`, the module installs Python, creates venvs, and deploys systemd services for both agents.
