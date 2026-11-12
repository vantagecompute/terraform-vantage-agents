# shellcheck shell=bash disable=SC2034
# Shared helpers for the install scripts. Sourced, never run on its own.
#
# Terraform uploads this file, install.env (settings, 0600) and one install
# script into a private staging directory on the node, runs the script as root,
# and the script removes the staging directory when it ends, so the secrets in
# install.env do not stay behind.

set -euo pipefail
umask 022

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
trap 'rm -rf "$HERE"' EXIT
# shellcheck disable=SC1091
. "$HERE/install.env"
AUTH_HEADER_FILE="$HERE/auth.header"

# Set to 1 by anything that changes the node. Scripts use it to decide whether
# a service needs a restart.
CHANGED=0

die() {
  echo "vantage-agents: $*" >&2
  exit 1
}

say() {
  echo "vantage-agents: $*"
}

sha256_of() {
  sha256sum "$1" | cut -d' ' -f1
}

# Fail early, with a clear message, when the node is not what this module needs.
preflight() {
  [ "$(id -u)" -eq 0 ] || die "the install script must run as root."

  # shellcheck disable=SC1091
  . /etc/os-release
  if [ "${ID:-}" != ubuntu ] || [ "${VERSION_ID:-}" != "26.04" ] || [ "$(uname -m)" != x86_64 ]; then
    die "this module supports Ubuntu 26.04 on x86_64 only. This node is ${ID:-unknown} ${VERSION_ID:-unknown} on $(uname -m)."
  fi

  local tool
  for tool in curl python3 systemctl; do
    command -v "$tool" >/dev/null || die "$tool is required on the node and was not found."
  done

  getent passwd "$SLURM_USER" >/dev/null || die "the Slurm user $SLURM_USER does not exist."

  local file
  for file in "$JWT_KEY_FILE" /usr/bin/scontrol; do
    [ -e "$file" ] || die "$file is missing. This module installs the Vantage agents on a node that already runs Slurm (for example the Vantage image); it does not install Slurm."
  done
}

# Trade the cluster's client credentials for a token the artifact CDN accepts.
# The secret goes to Python through the environment, so it never appears in a
# process list, and the token goes to curl through a file for the same reason.
get_token() {
  local token
  token=$(python3 - <<'PY'
import json
import os
import urllib.parse
import urllib.request

body = urllib.parse.urlencode({
    "grant_type": "client_credentials",
    "client_id": os.environ["CLIENT_ID"],
    "client_secret": os.environ["CLIENT_SECRET"],
}).encode()
request = urllib.request.Request(os.environ["OIDC_ISSUER"] + os.environ["TOKEN_PATH"], data=body)
with urllib.request.urlopen(request, timeout=30) as response:
    print(json.load(response)["access_token"])
PY
  ) || die "could not get a token from $OIDC_ISSUER. Check oidc_base_url, client_id and client_secret."
  (umask 077 && printf 'Authorization: Bearer %s\n' "$token" >"$AUTH_HEADER_FILE")
}

# Download one binary and verify it. Takes the binary name and a version or
# "latest". Sets:
#   STAGED         where the verified binary is
#   SHA            its sha256, as the CDN states it
#   NEEDS_INSTALL  1 when /usr/bin holds another build
# The checksum comes from the same CDN, with the same token, so it catches a
# damaged download, not a compromised CDN.
fetch_binary() {
  local name=$1 version=$2
  local url="${ARTIFACTS_URL%/}/binaries/$name/$ARCH/$version/$name"

  SHA=$(curl -fsS --max-time 60 -H "@$AUTH_HEADER_FILE" "$url.sha256" | awk '{print $1; exit}') \
    || die "could not fetch the checksum of $name $version from $ARTIFACTS_URL."
  [[ $SHA =~ ^[0-9a-f]{64}$ ]] || die "the checksum of $name $version is not a sha256."

  install -d -m 0750 -o root -g root "$STAGING_DIR"
  STAGED="$STAGING_DIR/$name"
  if [ ! -f "$STAGED" ] || [ "$(sha256_of "$STAGED")" != "$SHA" ]; then
    curl -fsS --max-time 300 -H "@$AUTH_HEADER_FILE" -o "$STAGED.part" "$url" \
      || die "could not download $name $version."
    if [ "$(sha256_of "$STAGED.part")" != "$SHA" ]; then
      rm -f "$STAGED.part"
      die "the download of $name $version does not match its checksum."
    fi
    chmod 0755 "$STAGED.part"
    mv "$STAGED.part" "$STAGED"
  fi

  NEEDS_INSTALL=1
  if [ -f "/usr/bin/$name" ] && [ "$(sha256_of "/usr/bin/$name")" = "$SHA" ]; then
    NEEDS_INSTALL=0
  fi
}

# Record what was installed, one line per binary: name, requested version,
# sha256. The same file and format v8x and the Ansible roles write.
record_lock() {
  local name=$1 version=$2 sha=$3
  local line="$name $version $sha" tmp
  install -d -m 0755 -o root -g root "$(dirname "$LOCK_FILE")"
  touch "$LOCK_FILE"
  if grep -qxF "$line" "$LOCK_FILE"; then
    return 0
  fi
  tmp=$(mktemp "$LOCK_FILE.XXXXXX")
  { grep -v "^$name " "$LOCK_FILE" || true; echo "$line"; } >"$tmp"
  chmod 0644 "$tmp"
  mv "$tmp" "$LOCK_FILE"
}

# Copy a file into place only when its content, mode or owner differ, and note
# the change. Takes: source, destination, mode, owner, group.
install_file() {
  local src=$1 dest=$2 mode=$3 owner=$4 group=$5
  if [ -f "$dest" ] && cmp -s "$src" "$dest" \
    && [ "$(stat -c '%a %U %G' "$dest")" = "${mode#0} $owner $group" ]; then
    return 0
  fi
  install -D -m "$mode" -o "$owner" -g "$group" "$src" "$dest"
  CHANGED=1
}
