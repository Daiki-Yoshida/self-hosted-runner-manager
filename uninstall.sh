#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" == "--purge" ]]; then
  echo 'Refusing to purge managed runner directories automatically.' >&2
  echo 'Remove each runner first with: runner-manager remove OWNER/REPO' >&2
  exit 2
fi

sudo rm -f /usr/local/bin/runner-manager
sudo rm -rf /usr/local/lib/self-hosted-runner-manager
printf 'Removed runner-manager binaries. Host configuration and registered runners were left untouched.\n'
