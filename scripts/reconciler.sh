#!/bin/bash
# slurm-accounts-reconciler: installed by its own systemd-setup, as v8x does.
# shellcheck disable=SC1091
. "$(dirname "$0")/lib.sh"

preflight
get_token

fetch_binary slurm-accounts-reconciler "$RECONCILER_VERSION"
if [ "$NEEDS_INSTALL" = 1 ]; then
  say "installing slurm-accounts-reconciler"
  "$STAGED" systemd-setup
  CHANGED=1
fi
record_lock slurm-accounts-reconciler "$RECONCILER_VERSION" "$SHA"

# The reconciler gets its own copy of the Slurm token signing key.
install_file "$JWT_KEY_FILE" "$RECONCILER_KEY_COPY" 0640 root slurm-accounts-reconciler
install_file "$HERE/slurm-accounts-reconciler.env" "$RECONCILER_DIR/env" 0600 root root

# Order the reconciler after the Slurm daemons. When the image ships its
# identity helper (it makes the slurm user an Operator in accounting), run it
# first, as root, and allow it time to wait for slurmdbd on a first boot.
{
  echo "# Managed by Terraform (module terraform-vantage-agents)."
  echo "[Unit]"
  echo "After=slurmctld.service slurmdbd.service slurmrestd.service"
  echo
  echo "[Service]"
  if [ -e "$RECONCILER_IDENTITY_HELPER" ]; then
    echo "ExecStartPre=+$RECONCILER_IDENTITY_HELPER"
    echo "TimeoutStartSec=180"
  fi
} >"$HERE/dropin.conf"
install_file "$HERE/dropin.conf" /etc/systemd/system/slurm-accounts-reconciler.service.d/10-vantage-agents.conf 0644 root root

# The image's path unit would start the reconciler on its own; the enabled
# service alone does that here.
if [ -e /usr/lib/systemd/system/slurm-accounts-reconciler.path ]; then
  systemctl disable --now slurm-accounts-reconciler.path
fi

systemctl daemon-reload
systemctl enable slurm-accounts-reconciler.service
if [ "$CHANGED" = 1 ]; then
  systemctl restart slurm-accounts-reconciler.service
else
  systemctl start slurm-accounts-reconciler.service
fi
say "slurm-accounts-reconciler is installed"
