#!/usr/bin/env bash
set -Eeuo pipefail

REPO="Daiki-Yoshida/self-hosted-runner-manager"
REF="${SHRM_REF:-main}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ "$(uname -s)" == "Linux" ]] || { echo 'Linux only.' >&2; exit 1; }
for cmd in curl tar; do
  command -v "$cmd" >/dev/null || { echo "Required command missing: $cmd" >&2; exit 1; }
done

ARCHIVE="$TMP/source.tar.gz"
URL="https://codeload.github.com/${REPO}/tar.gz/${REF}"
printf '[bootstrap] Downloading %s at ref %s\n' "$REPO" "$REF"
curl --fail --location --proto '=https' --tlsv1.2 --output "$ARCHIVE" "$URL"

tar -xzf "$ARCHIVE" -C "$TMP"
SOURCE_DIR="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n1)"
[[ -n "$SOURCE_DIR" && -x "$SOURCE_DIR/install.sh" ]] || { echo 'Downloaded archive did not contain install.sh.' >&2; exit 1; }

printf '[bootstrap] Running reviewed project installer from %s\n' "$SOURCE_DIR"
"$SOURCE_DIR/install.sh"
