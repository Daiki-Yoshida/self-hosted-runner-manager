#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="/usr/local/lib/self-hosted-runner-manager"
BIN="/usr/local/bin/runner-manager"

[[ "$(uname -s)" == "Linux" ]] || { echo 'Linux only.' >&2; exit 1; }
[[ "${EUID}" -ne 0 ]] || { echo 'Run this script as a normal admin user; it invokes sudo itself.' >&2; exit 1; }
command -v sudo >/dev/null || { echo 'sudo is required.' >&2; exit 1; }

for cmd in curl tar sha256sum python3; do
  command -v "$cmd" >/dev/null || { echo "Required command missing: $cmd" >&2; exit 1; }
done

sudo install -d -m 0755 "$DEST/bin" "$DEST/lib"
sudo install -m 0755 "$ROOT_DIR/bin/runner-manager" "$DEST/bin/runner-manager"
sudo install -m 0644 "$ROOT_DIR/lib/common.sh" "$DEST/lib/common.sh"
sudo ln -sfn "$DEST/bin/runner-manager" "$BIN"

echo "Installed: $BIN"
echo "No GitHub CLI authentication is required on this host."
echo "Next: runner-manager init --profile xserver"
