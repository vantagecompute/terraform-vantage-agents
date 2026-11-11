# terraform-vantage-agents

A Terraform module that installs the Vantage agents on a Slurm node over SSH and connects it to a Vantage cluster:

- **cluster-presence-agent** reports once a minute that this cluster is alive, which is what makes it show as Connected in Vantage. It is installed last.
- **slurm-accounts-reconciler** keeps Slurm users and accounts in step with the LDAP directory of your Vantage organization.
- **vref-agent** watches job state on the cluster and reports it to vref-api. It runs as a systemd timer, makes only outbound calls, and holds no database credential.

This module replaces the old `vantage-agent` and `jobbergate-agent` install (snap or PyPI), which is retired. See [Upgrading from 1.x](#upgrading-from-1x).

Terraform is the optional way to provision these components. The Ansible role [`vantage_agents`](https://github.com/vantagecompute/ansible-role-vantage_agents) installs the same things and is the default path of the Vantage Compute `v8x` tool. The tunnel and the auth proxy are a separate module, `terraform-vantage-tunnel`.

## What this module does not do

It does not install Slurm, MariaDB, InfluxDB or SSSD. The node must already run Slurm with slurmrestd and a JWT signing key at `/etc/slurm/jwt_hs256.key`, as the Vantage image does. The install scripts check this first and stop with a clear message when something is missing.

## Requirements

- Terraform 1.4 or newer.
- A node running Ubuntu 26.04 on x86_64. Other platforms are not supported yet.
- SSH access to the node as root, or as a user with passwordless `sudo`.
- `curl`, `python3` and `systemd` on the node (a stock Ubuntu 26.04 server has them).
- A Vantage cluster and its Keycloak client credentials. The client ID is the cluster ID.
- Outbound HTTPS from the node to the artifact CDN, the Keycloak realm, the Vantage API and vref-api.
- A Slurm that lets the `vrefagent` user see every user's jobs: no `PrivateData=jobs` in `slurm.conf`, and either none in `slurmdbd.conf` or `vrefagent` as an accounting operator.

## Usage

```hcl
module "vantage_agents" {
  source = "github.com/vantagecompute/terraform-vantage-agents"

  host            = "10.0.0.5"
  ssh_user        = "ubuntu"
  ssh_private_key = file("~/.ssh/id_ed25519")

  client_id     = var.cluster_id
  client_secret = var.cluster_client_secret
  oidc_base_url = "https://auth.vantagecompute.ai"
  api_base_url  = "https://apis.vantagecompute.ai"

  ldap_url             = "ldaps://ldap.vantagecompute.ai"
  ldap_organization_id = var.organization_id
  ldap_bind_password   = var.ldap_bind_password

  vref_api_url = "https://vref.example.com"

  reconciler_version     = "X.Y.Z"
  vref_agent_version     = "X.Y.Z"
  presence_agent_version = "X.Y.Z"
}
```

## Variables

Required:

| Name | Meaning |
| --- | --- |
| `host` | IP address or DNS name of the node. |
| `ssh_user` | SSH user. Root, or a user with passwordless `sudo`. |
| `ssh_private_key` | The contents of the SSH private key (use `file()`), not a path. |
| `client_id` | The cluster's Keycloak client ID, which is the cluster ID. |
| `client_secret` | The client secret. |
| `oidc_base_url` | Keycloak base URL without `/realms/vantage`. |
| `api_base_url` | Base URL of the Vantage API the presence agent reports to. |
| `ldap_url` | LDAP URL of your organization. |
| `ldap_organization_id` | Your organization ID. |
| `ldap_bind_password` | The LDAP bind password. |
| `vref_api_url` | Base URL of vref-api. Required while `install_vref_agent` is true. |

Optional:

| Name | Default | Meaning |
| --- | --- | --- |
| `ssh_port` | `22` | SSH port of the node. |
| `install_vref_agent` | `true` | Install vref-agent. |
| `install_presence_agent` | `true` | Install the presence agent. |
| `artifacts_url` | `https://vantage-artifacts.vantagecompute.ai` | Where the binaries are downloaded from. |
| `reconciler_version` | `latest` | Reconciler version. Pin it in production. |
| `vref_agent_version` | `latest` | vref-agent version. Pin it in production. |
| `presence_agent_version` | `latest` | Presence agent version. Pin it in production. |
| `slurmrestd_url` | `http://127.0.0.1:6820` | The cluster's slurmrestd. |
| `slurm_user` | `slurm` | The user slurmctld runs as. |
| `vref_container_engine` | empty | `pyxis` or `apptainer`; leave empty when the cluster runs neither. |
| `slurm_token_lifespan` | `604800` | Seconds a vref-agent Slurm token lives. |
| `slurm_token_refresh` | `daily` | A systemd `OnCalendar` value for re-minting it. |

The output `installed_components` lists what the module installed.

## How it works

Each component is one `terraform_data` resource. It uploads a private staging directory to the node (settings, a template or two, and an install script), runs the script as root, and the script deletes the directory when it ends, so the secrets in it do not stay behind. The script gets a Keycloak token with the cluster's credentials, downloads the binary and its `.sha256` file from the artifact CDN, checks the checksum, and, when `/usr/bin` holds a different build, runs the binary's own `systemd-setup` command, which creates the service user, directories and unit. It then writes the root-only (`0600`) settings file and starts the service.

The resources run in order: reconciler, vref-agent, presence agent. A resource runs again only when its inputs change: a version, a setting, or the module's own scripts. A second `terraform apply` changes nothing. The scripts are idempotent too, so `terraform apply -replace=...` is safe.

The module records what it installed, one line per binary (name, requested version, sha256), in `/etc/vantage/artifacts.lock`, the same file and format `v8x` and the Ansible roles write.

The checksum comes from the same CDN as the binary, so it catches a damaged download, not a compromised CDN.

For vref-agent the module also creates a `vrefagent` system user and mints a Slurm token for it with `scontrol token`, then refreshes it on a systemd timer, because the agent reads that token on every call and never mints one itself. The slurmctld wake-up hook is not wired: that means editing `slurm.conf`, which belongs to whoever owns your Slurm configuration.

## Things to know

- **`latest` is not tracked.** Terraform cannot see that the CDN's `latest` moved, so it does not reinstall. Pin versions, and to pick up a new `latest` run `terraform apply -replace='module.vantage_agents.terraform_data.reconciler'` (and the same for the others).
- **Protect your state.** Terraform stores the client secret and the LDAP password in its state file, even though the variables are `sensitive`. Use an encrypted remote backend or restrict access to the state.
- **`terraform destroy` does not uninstall.** It forgets the resources and leaves the agents on the node.
- **vref-agent needs 0.1.5 or newer.** Releases from 0.1.5 include the on-cluster agent and its `systemd-setup` command. The older 0.1.3 build is the cloud-side agent and has none, so the install script stops with a clear message. Set `install_vref_agent = false` to leave it out.
- **The LDAP base DN is fixed** to `dc=vantagecompute,dc=ai`, so the reconciler works against the Vantage-hosted directory only.
- **Image helper.** When the node has `/opt/vantage/bin/slurm-accounts-reconciler-identity` (the Vantage image does), the reconciler runs it before it starts, so the Slurm user is an accounting operator.

## Upgrading from 1.x

This is a breaking change. The `vantage-agent` and `jobbergate-agent` installs, and the `install_type` and `cluster_name` variables, are gone. `oidc_client_id` and `oidc_client_secret` are now `client_id` and `client_secret`, and the module needs more inputs (see Variables). The module does not remove the old agents; stop and remove them on the node yourself before you apply.

## Testing

`just lint` runs `terraform fmt`, `terraform validate` and `shellcheck`. `just test <user> <host> <port> <key>` prepares a throwaway Ubuntu 26.04 VM with a stub token endpoint and artifact server, applies the module to it, checks that a second plan is empty, and checks the result on the node. It proves the module's logic only. It does not prove the real binaries, the real `systemd-setup`, or that a cluster shows up in Vantage; for that, apply the module to a host from the Vantage image with a real cluster.

## License

Apache 2.0. See `LICENSE`.

## Copyright

Copyright 2025 Vantage Compute Corporation.

## Contact

For questions, support, or to report issues, please contact:

- GitHub Issues: https://github.com/vantagecompute/terraform-vantage-agents/issues
- Email: support@vantagecompute.com
