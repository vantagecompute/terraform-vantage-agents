#!/bin/bash
# vref-agent: a timer-driven pass, installed by its own systemd-setup. It reads
# slurmrestd with a Slurm token for its own user, which this script mints and
# refreshes on a timer (the agent never mints one itself).
# shellcheck disable=SC1091
. "$(dirname "$0")/lib.sh"

preflight
get_token

fetch_binary vref-agent "$VREF_AGENT_VERSION"

# The Slurm identity vref-agent reads as.
if ! id -u "$VREF_SLURM_IDENTITY" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$VREF_SLURM_IDENTITY"
fi

if [ "$NEEDS_INSTALL" = 1 ]; then
  # The vref-agent build the CDN served up to 0.1.3 is the older cloud-side
  # agent and has no systemd-setup. Say so, instead of failing obscurely.
  help=$("$STAGED" systemd-setup --help 2>&1 || true)
  case $help in
    *systemd-setup*) ;;
    *) die "the vref-agent build $VREF_AGENT_VERSION that the artifact CDN served has no systemd-setup command, so it cannot be installed as a service. It is the older cloud-side agent. Set vref_agent_version to a release that includes the on-cluster agent, or set install_vref_agent to false." ;;
  esac
  say "installing vref-agent"
  "$STAGED" systemd-setup --slurm-user "$SLURM_USER"
fi
record_lock vref-agent "$VREF_AGENT_VERSION" "$SHA"

install_file "$HERE/vref-agent.env" "$VREF_DIR/env" 0600 root root
install_file "$HERE/vref-agent-slurm-token.sh" "$VREF_TOKEN_SCRIPT" 0750 root root
install_file "$HERE/vref-agent-slurm-token.service" /etc/systemd/system/vref-agent-slurm-token.service 0644 root root
install_file "$HERE/vref-agent-slurm-token.timer" /etc/systemd/system/vref-agent-slurm-token.timer 0644 root root

systemctl daemon-reload

[ -e "$VREF_TOKEN_FILE" ] || "$VREF_TOKEN_SCRIPT"

systemctl enable --now vref-agent-slurm-token.timer
systemctl enable --now vref-agent.timer vref-agent.path
say "vref-agent is installed"
