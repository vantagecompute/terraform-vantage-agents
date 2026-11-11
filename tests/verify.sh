#!/bin/bash
# Check what the module left on the node. Test use only. Run as root:
#   ssh user@vm 'sudo bash -s' < tests/verify.sh
set -uo pipefail
fail=0
check() { # check "description" command...
  local what=$1
  shift
  if "$@" >/dev/null 2>&1; then echo "ok    $what"; else echo "FAIL  $what"; fail=1; fi
}
# shellcheck disable=SC2329  # called through check()
mode_owner() { [ "$(stat -c '%a %U' "$1")" = "$2 $3" ]; }

check "reconciler env is 0600 root" mode_owner /etc/vantage/slurm-accounts-reconciler/env 600 root
check "vref-agent env is 0600 root" mode_owner /etc/vantage/vref-agent/env 600 root
check "presence agent env is 0600 root" mode_owner /etc/vantage/cluster-presence-agent/env 600 root
check "reconciler key copy is 0640 root" mode_owner /etc/vantage/slurm-accounts-reconciler/jwt_hs256.key 640 root
check "vref-agent slurm token is 0640 root" mode_owner /etc/vantage/vref-agent/slurm.token 640 root

# The test secret is: a "quoted" \ it's secret
check "the secret is escaped for systemd" \
  grep -qxF 'VREF_AGENT_CLIENT_SECRET="a \"quoted\" \\ it'"'"'s secret"' /etc/vantage/vref-agent/env

for f in /etc/vantage/slurm-accounts-reconciler/env /etc/vantage/vref-agent/env /etc/vantage/cluster-presence-agent/env; do
  check "every line of $f is a comment or KEY=\"value\"" \
    bash -c "! grep -qvE '^(#.*|[A-Z][A-Z0-9_]*=\".*\")\$' $f"
done
check "first setting of the reconciler env is on its own line" bash -c "sed -n 2p /etc/vantage/slurm-accounts-reconciler/env | grep -q '^SLURM_ACCOUNTS_RECONCILER_LDAP_URI='"
check "first setting of the vref-agent env is on its own line" bash -c "sed -n 2p /etc/vantage/vref-agent/env | grep -q '^VREF_AGENT_API_URL='"
check "first setting of the presence env is on its own line" bash -c "sed -n 2p /etc/vantage/cluster-presence-agent/env | grep -q '^CLUSTER_PRESENCE_AGENT_OIDC_DOMAIN='"

for name in slurm-accounts-reconciler vref-agent cluster-presence-agent; do
  check "the lock file has a line for $name" grep -Eq "^$name [^ ]+ [0-9a-f]{64}\$" /etc/vantage/artifacts.lock
done

for unit in slurm-accounts-reconciler.service vref-agent.timer vref-agent.path vref-agent-slurm-token.timer cluster-presence-agent.timer; do
  check "$unit is enabled" systemctl is-enabled "$unit"
done
check "the reconciler is running" systemctl is-active slurm-accounts-reconciler.service
check "no staging directory is left behind" bash -c '! ls -d /tmp/vantage-agents-* 2>/dev/null | grep -q .'

exit "$fail"
