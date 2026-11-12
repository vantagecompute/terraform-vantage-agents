#!/bin/bash
# cluster-presence-agent: reports this cluster's presence to Vantage once a
# minute, which is what makes the cluster show as Connected. Installed by its
# own systemd-setup, as v8x does.
# shellcheck disable=SC1091
. "$(dirname "$0")/lib.sh"

preflight
get_token

fetch_binary cluster-presence-agent "$PRESENCE_AGENT_VERSION"
if [ "$NEEDS_INSTALL" = 1 ]; then
  say "installing cluster-presence-agent"
  "$STAGED" systemd-setup
fi
record_lock cluster-presence-agent "$PRESENCE_AGENT_VERSION" "$SHA"

install_file "$HERE/cluster-presence-agent.env" "$PRESENCE_DIR/env" 0600 root root

systemctl daemon-reload
systemctl enable --now cluster-presence-agent.timer
say "cluster-presence-agent is installed"
