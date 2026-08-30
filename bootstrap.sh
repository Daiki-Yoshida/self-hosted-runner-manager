#!/usr/bin/env bash
set -Eeuo pipefail

REPO="Daiki-Yoshida/self-hosted-runner-manager"
API="https://api.github.com/repos/${REPO}/releases/latest"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ "$(uname -s)" == "Linux" ]] || { echo 'Linux only.' >&2; exit 1; }
for cmd in curl tar python3; do command -v "$cmd" >/dev/null || { echo "Required command missing: $cmd" >&2; exit 1; }; done

if [[ -n "${SHRM_REF:-}" && -n "${SHRM_VERSION:-}" ]]; then
  echo 'Set only one of SHRM_REF or SHRM_VERSION.' >&2
  exit 2
fi

if [[ -n "${SHRM_REF:-}" ]]; then
  REF="$SHRM_REF"
  SOURCE="explicit ref"
elif [[ -n "${SHRM_VERSION:-}" ]]; then
  [[ "$SHRM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'SHRM_VERSION must be X.Y.Z.' >&2; exit 2; }
  REF="v${SHRM_VERSION}"
  SOURCE="pinned version"
else
  if RELEASE_JSON="$(curl --fail --silent --show-error --location -H 'Accept: application/vnd.github+json' "$API" 2>/dev/null)"; then
    REF="$(printf '%s' "$RELEASE_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); t=d.get("tag_name", ""); print(t if t else "")')"
  else
    REF=""
  fi
  if [[ -n "$REF" ]]; then
    SOURCE="latest stable GitHub Release"
  else
    REF="main"
    SOURCE="main fallback (no public Release found)"
    printf '[bootstrap] WARN: no public GitHub Release was found; falling back to main.\n' >&2
    printf '[bootstrap] For immutable installs, set SHRM_VERSION=X.Y.Z or SHRM_REF=<tag-or-commit>.\n' >&2
  fi
fi

ARCHIVE="$TMP/source.tar.gz"
URL="https://codeload.github.com/${REPO}/tar.gz/${REF}"
printf '[bootstrap] Source: %s (%s)\n' "$REF" "$SOURCE"
printf '[bootstrap] Downloading %s\n' "$URL"
curl --fail --location --proto '=https' --tlsv1.2 --output "$ARCHIVE" "$URL"

tar -xzf "$ARCHIVE" -C "$TMP"
SOURCE_DIR="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n1)"
[[ -n "$SOURCE_DIR" && -x "$SOURCE_DIR/install.sh" ]] || { echo 'Downloaded archive did not contain install.sh.' >&2; exit 1; }

printf '[bootstrap] Running project installer from ref %s\n' "$REF"
"$SOURCE_DIR/install.sh"
