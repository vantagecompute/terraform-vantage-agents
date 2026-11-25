# Installs the Vantage agents on a node that already runs Slurm, over SSH:
# slurm-accounts-reconciler, vref-agent and cluster-presence-agent.
#
# Each component is one terraform_data resource that uploads a private staging
# directory (settings, templates and an install script) and runs the script as
# root. The script is idempotent. A resource runs again only when its inputs
# change (a version, a setting, or the module's own scripts), so a second apply
# changes nothing.

locals {
  oidc_issuer  = "${trim(var.oidc_base_url, "/")}/realms/vantage"
  api_base_url = trim(var.api_base_url, "/")

  # Fixed by the Vantage image and the binaries, not part of the interface.
  arch                   = "linux-amd64"
  token_path             = "/protocol/openid-connect/token"
  lock_file              = "/etc/vantage/artifacts.lock"
  staging_dir            = "/var/cache/vantage-agents"
  jwt_key_file           = "/etc/slurm/jwt_hs256.key"
  reconciler_dir         = "/etc/vantage/slurm-accounts-reconciler"
  reconciler_key_copy    = "/etc/vantage/slurm-accounts-reconciler/jwt_hs256.key"
  reconciler_helper      = "/opt/vantage/bin/slurm-accounts-reconciler-identity"
  vref_dir               = "/etc/vantage/vref-agent"
  vref_token_file        = "/etc/vantage/vref-agent/slurm.token"
  vref_slurm_identity    = "vrefagent"
  vref_token_script_path = "/usr/local/sbin/vref-agent-slurm-token"
  presence_dir           = "/etc/vantage/cluster-presence-agent"
  presence_interval      = 60
  ldap_base_dn           = "dc=vantagecompute,dc=ai"
  run_as_root            = "if [ \"$(id -u)\" -eq 0 ]; then bash %s; else sudo -n bash %s; fi"

  # Values for the systemd env files sit inside double quotes, so a backslash
  # and a double quote must be escaped.
  env = {
    for name, value in {
      client_id            = var.client_id
      client_secret        = var.client_secret
      ldap_url             = var.ldap_url
      ldap_organization_id = var.ldap_organization_id
      ldap_bind_password   = var.ldap_bind_password
    } : name => replace(replace(value, "\\", "\\\\"), "\"", "\\\"")
  }

  # Settings for the install scripts, quoted for the shell. A component gets
  # the shared settings plus its own, so changing one component's version does
  # not rerun the others.
  shell_settings = {
    for group, settings in {
      common = {
        CLIENT_ID     = var.client_id
        CLIENT_SECRET = var.client_secret
        OIDC_ISSUER   = local.oidc_issuer
        TOKEN_PATH    = local.token_path
        ARTIFACTS_URL = var.artifacts_url
        ARCH          = local.arch
        LOCK_FILE     = local.lock_file
        STAGING_DIR   = local.staging_dir
        SLURM_USER    = var.slurm_user
        JWT_KEY_FILE  = local.jwt_key_file
      }
      reconciler = {
        RECONCILER_VERSION         = coalesce(var.reconciler_version, var.release_track)
        RECONCILER_DIR             = local.reconciler_dir
        RECONCILER_KEY_COPY        = local.reconciler_key_copy
        RECONCILER_IDENTITY_HELPER = local.reconciler_helper
      }
      vref = {
        VREF_AGENT_VERSION  = coalesce(var.vref_agent_version, var.release_track)
        VREF_DIR            = local.vref_dir
        VREF_TOKEN_FILE     = local.vref_token_file
        VREF_TOKEN_SCRIPT   = local.vref_token_script_path
        VREF_SLURM_IDENTITY = local.vref_slurm_identity
      }
      presence = {
        PRESENCE_AGENT_VERSION = coalesce(var.presence_agent_version, var.release_track)
        PRESENCE_DIR           = local.presence_dir
      }
    } : group => { for name, value in settings : name => "'${replace(value, "'", "'\\''")}'" }
  }

  install_env = {
    for component in ["reconciler", "vref", "presence"] : component => templatefile(
      "${path.module}/templates/install.env.tftpl",
      { settings = merge(local.shell_settings.common, local.shell_settings[component]) }
    )
  }

  reconciler_env = templatefile("${path.module}/templates/slurm-accounts-reconciler.env.tftpl", {
    ldap_url             = local.env.ldap_url
    ldap_organization_id = local.env.ldap_organization_id
    ldap_bind_password   = local.env.ldap_bind_password
    client_id            = local.env.client_id
    ldap_base_dn         = local.ldap_base_dn
    slurmrestd_url       = var.slurmrestd_url
    slurm_user           = var.slurm_user
    key_file             = local.reconciler_key_copy
  })

  vref_env = templatefile("${path.module}/templates/vref-agent.env.tftpl", {
    vref_api_url     = var.vref_api_url
    oidc_issuer      = local.oidc_issuer
    client_id        = local.env.client_id
    client_secret    = local.env.client_secret
    slurmrestd_url   = var.slurmrestd_url
    token_file       = local.vref_token_file
    container_engine = var.vref_container_engine
  })
  vref_token_script_body = templatefile("${path.module}/templates/vref-agent-slurm-token.sh.tftpl", {
    identity   = local.vref_slurm_identity
    vref_dir   = local.vref_dir
    lifespan   = var.slurm_token_lifespan
    token_file = local.vref_token_file
  })
  vref_token_service = templatefile("${path.module}/templates/vref-agent-slurm-token.service.tftpl", {
    script = local.vref_token_script_path
  })
  vref_token_timer = templatefile("${path.module}/templates/vref-agent-slurm-token.timer.tftpl", {
    refresh = var.slurm_token_refresh
  })

  presence_env = templatefile("${path.module}/templates/cluster-presence-agent.env.tftpl", {
    oidc_domain      = trimprefix(trimprefix(local.oidc_issuer, "https://"), "http://")
    client_id        = local.env.client_id
    client_secret    = local.env.client_secret
    use_https        = startswith(var.oidc_base_url, "http://") ? "false" : "true"
    api_base_url     = local.api_base_url
    interval_seconds = local.presence_interval
  })

  # One private staging directory per component on the node.
  stage = {
    reconciler = "/tmp/vantage-agents-reconciler"
    vref       = "/tmp/vantage-agents-vref-agent"
    presence   = "/tmp/vantage-agents-presence-agent"
  }
}

resource "terraform_data" "reconciler" {
  triggers_replace = [sha256(join("\n", [
    local.install_env.reconciler,
    local.reconciler_env,
    file("${path.module}/scripts/lib.sh"),
    file("${path.module}/scripts/reconciler.sh"),
  ]))]

  connection {
    type        = "ssh"
    host        = var.host
    port        = var.ssh_port
    user        = var.ssh_user
    private_key = var.ssh_private_key
    agent       = false
  }

  provisioner "remote-exec" {
    inline = ["rm -rf ${local.stage.reconciler}", "mkdir -m 0700 ${local.stage.reconciler}"]
  }
  provisioner "file" {
    content     = local.install_env.reconciler
    destination = "${local.stage.reconciler}/install.env"
  }
  provisioner "file" {
    source      = "${path.module}/scripts/lib.sh"
    destination = "${local.stage.reconciler}/lib.sh"
  }
  provisioner "file" {
    source      = "${path.module}/scripts/reconciler.sh"
    destination = "${local.stage.reconciler}/reconciler.sh"
  }
  provisioner "file" {
    content     = local.reconciler_env
    destination = "${local.stage.reconciler}/slurm-accounts-reconciler.env"
  }
  provisioner "remote-exec" {
    inline = [format(local.run_as_root, "${local.stage.reconciler}/reconciler.sh", "${local.stage.reconciler}/reconciler.sh")]
  }
}

resource "terraform_data" "vref_agent" {
  count      = var.install_vref_agent ? 1 : 0
  depends_on = [terraform_data.reconciler]

  triggers_replace = [sha256(join("\n", [
    local.install_env.vref,
    local.vref_env,
    local.vref_token_script_body,
    local.vref_token_service,
    local.vref_token_timer,
    file("${path.module}/scripts/lib.sh"),
    file("${path.module}/scripts/vref_agent.sh"),
  ]))]

  lifecycle {
    precondition {
      condition     = var.vref_api_url != ""
      error_message = "vref_api_url is required when install_vref_agent is true."
    }
  }

  connection {
    type        = "ssh"
    host        = var.host
    port        = var.ssh_port
    user        = var.ssh_user
    private_key = var.ssh_private_key
    agent       = false
  }

  provisioner "remote-exec" {
    inline = ["rm -rf ${local.stage.vref}", "mkdir -m 0700 ${local.stage.vref}"]
  }
  provisioner "file" {
    content     = local.install_env.vref
    destination = "${local.stage.vref}/install.env"
  }
  provisioner "file" {
    source      = "${path.module}/scripts/lib.sh"
    destination = "${local.stage.vref}/lib.sh"
  }
  provisioner "file" {
    source      = "${path.module}/scripts/vref_agent.sh"
    destination = "${local.stage.vref}/vref_agent.sh"
  }
  provisioner "file" {
    content     = local.vref_env
    destination = "${local.stage.vref}/vref-agent.env"
  }
  provisioner "file" {
    content     = local.vref_token_script_body
    destination = "${local.stage.vref}/vref-agent-slurm-token.sh"
  }
  provisioner "file" {
    content     = local.vref_token_service
    destination = "${local.stage.vref}/vref-agent-slurm-token.service"
  }
  provisioner "file" {
    content     = local.vref_token_timer
    destination = "${local.stage.vref}/vref-agent-slurm-token.timer"
  }
  provisioner "remote-exec" {
    inline = [format(local.run_as_root, "${local.stage.vref}/vref_agent.sh", "${local.stage.vref}/vref_agent.sh")]
  }
}

# Last, so Vantage shows the cluster as Connected only once everything else is
# installed.
resource "terraform_data" "presence_agent" {
  count      = var.install_presence_agent ? 1 : 0
  depends_on = [terraform_data.reconciler, terraform_data.vref_agent]

  triggers_replace = [sha256(join("\n", [
    local.install_env.presence,
    local.presence_env,
    file("${path.module}/scripts/lib.sh"),
    file("${path.module}/scripts/presence_agent.sh"),
  ]))]

  connection {
    type        = "ssh"
    host        = var.host
    port        = var.ssh_port
    user        = var.ssh_user
    private_key = var.ssh_private_key
    agent       = false
  }

  provisioner "remote-exec" {
    inline = ["rm -rf ${local.stage.presence}", "mkdir -m 0700 ${local.stage.presence}"]
  }
  provisioner "file" {
    content     = local.install_env.presence
    destination = "${local.stage.presence}/install.env"
  }
  provisioner "file" {
    source      = "${path.module}/scripts/lib.sh"
    destination = "${local.stage.presence}/lib.sh"
  }
  provisioner "file" {
    source      = "${path.module}/scripts/presence_agent.sh"
    destination = "${local.stage.presence}/presence_agent.sh"
  }
  provisioner "file" {
    content     = local.presence_env
    destination = "${local.stage.presence}/cluster-presence-agent.env"
  }
  provisioner "remote-exec" {
    inline = [format(local.run_as_root, "${local.stage.presence}/presence_agent.sh", "${local.stage.presence}/presence_agent.sh")]
  }
}
