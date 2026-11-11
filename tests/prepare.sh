#!/bin/bash
# Make a bare Ubuntu 26.04 VM look like the Vantage image as far as the module
# can tell, and start the stub CDN. Test use only. Run as root on the VM, with
# stub_cdn.py next to this file:
#   scp tests/stub_cdn.py tests/prepare.sh user@vm: && ssh user@vm 'sudo bash prepare.sh'
set -euo pipefail

id -u slurm >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin slurm
install -d -m 0755 /etc/slurm
install -m 0600 -o slurm -g slurm <(echo "not a real key") /etc/slurm/jwt_hs256.key
install -m 0755 <(printf '#!/bin/sh\necho "SLURM_JWT=fake.token.value"\n') /usr/bin/scontrol

install -m 0755 "$(dirname "$0")/stub_cdn.py" /usr/local/bin/stub_cdn.py
cat >/etc/systemd/system/stub-cdn.service <<'UNIT'
[Unit]
Description=Stub Vantage artifact CDN
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/stub_cdn.py 8099
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now stub-cdn.service
