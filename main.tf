# Combined install for vantage-agent and jobbergate-agent (Snap or PyPI)

locals {
  install_type = lower(var.install_type)
}

resource "null_resource" "install_agents_snap" {
  count = local.install_type == "snap" ? 1 : 0
  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = var.ssh_private_key
    host        = var.host
  }
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y snapd",
      "sudo snap install vantage-agent --classic",
      "sudo snap set vantage-agent oidc-client-id=${var.oidc_client_id} oidc-client-secret=${var.oidc_client_secret} cluster-name=${var.cluster_name}",
      "sudo snap install jobbergate-agent --classic",
      "sudo snap set jobbergate-agent oidc-client-id=${var.oidc_client_id} oidc-client-secret=${var.oidc_client_secret}",
      "sudo systemctl enable snap.vantage-agent.daemon",
      "sudo systemctl start snap.vantage-agent.daemon",
      "sudo systemctl enable snap.jobbergate-agent.daemon",
      "sudo systemctl start snap.jobbergate-agent.daemon"
    ]
  }
}

resource "null_resource" "install_agents_pypi" {
  count = local.install_type == "pypi" ? 1 : 0
  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = var.ssh_private_key
    host        = var.host
  }
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y python3 python3-pip python3-venv",
      "sudo mkdir -p /srv/vantage-agent-venv /srv/jobbergate-agent-venv /etc/vantage-agent /etc/jobbergate-agent",
      "python3 -m venv /srv/vantage-agent-venv",
      "python3 -m venv /srv/jobbergate-agent-venv",
      "/srv/vantage-agent-venv/bin/pip install vantage-agent",
      "/srv/jobbergate-agent-venv/bin/pip install jobbergate-agent"
    ]
  }
  provisioner "file" {
    content     = templatefile("${path.module}/templates/vantage-agent.env.tmpl", {
      oidc_client_id     = var.oidc_client_id,
      oidc_client_secret = var.oidc_client_secret,
      cluster_name       = var.cluster_name
    })
    destination = "/tmp/vantage-agent.env"
  }
  provisioner "file" {
    content     = templatefile("${path.module}/templates/jobbergate-agent.env.tmpl", {
      oidc_client_id     = var.oidc_client_id,
      oidc_client_secret = var.oidc_client_secret
    })
    destination = "/tmp/jobbergate-agent.env"
  }
  provisioner "file" {
    content     = templatefile("${path.module}/templates/vantage-agent.service.tmpl", {})
    destination = "/tmp/vantage-agent.service"
  }
  provisioner "file" {
    content     = templatefile("${path.module}/templates/jobbergate-agent.service.tmpl", {})
    destination = "/tmp/jobbergate-agent.service"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/vantage-agent.env /etc/vantage-agent/vantage-agent.env",
      "sudo mv /tmp/jobbergate-agent.env /etc/jobbergate-agent/jobbergate-agent.env",
      "sudo mv /tmp/vantage-agent.service /etc/systemd/system/vantage-agent.service",
      "sudo mv /tmp/jobbergate-agent.service /etc/systemd/system/jobbergate-agent.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable vantage-agent",
      "sudo systemctl start vantage-agent",
      "sudo systemctl enable jobbergate-agent",
      "sudo systemctl start jobbergate-agent"
    ]
  }
}
