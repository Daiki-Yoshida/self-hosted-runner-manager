#!/usr/bin/env bash

SHRM_NAME="self-hosted-runner-manager"
SHRM_VERSION="0.2.0"
SHRM_ETC_DIR="${SHRM_ETC_DIR:-/etc/self-hosted-runner-manager}"
SHRM_CONFIG_FILE="${SHRM_CONFIG_FILE:-${SHRM_ETC_DIR}/config}"
SHRM_STATE_DIR="${SHRM_STATE_DIR:-${SHRM_ETC_DIR}/runners}"
SHRM_DEFAULT_RUNNER_ROOT="/opt/github-actions-runners"
SHRM_DEFAULT_RUNNER_USER="gha-runner"
SHRM_DEFAULT_CACHE_DIR="/var/cache/self-hosted-runner-manager"
SHRM_GITHUB_API_VERSION="${SHRM_GITHUB_API_VERSION:-2026-03-10}"
SHRM_RUNNER_RELEASE_API="https://api.github.com/repos/actions/runner/releases"

log() { printf '[runner-manager] %s\n' "$*"; }
warn() { printf '[runner-manager] WARN: %s\n' "$*" >&2; }
die() { printf '[runner-manager] ERROR: %s\n' "$*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "Only Linux hosts are supported."
}

require_not_root() {
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die "Run runner-manager as your normal admin user, not as root. It uses sudo only when required."
}

require_systemd() {
  [[ -d /run/systemd/system ]] || die "systemd is not active. Enable systemd first (including in WSL) before using this version."
  command -v systemctl >/dev/null 2>&1 || die "systemctl is required."
}

normalize_repo() {
  local value="${1:-}"
  value="${value#https://github.com/}"
  value="${value#http://github.com/}"
  value="${value%.git}"
  value="${value%/}"
  [[ "$value" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
  printf '%s\n' "$value"
}

repo_owner() { printf '%s\n' "${1%%/*}"; }
repo_name() { printf '%s\n' "${1#*/}"; }

sanitize_component() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-')"
  value="${value#-}"
  value="${value%-}"
  printf '%s\n' "$value"
}

repo_key() {
  local repo="$1"
  printf '%s--%s\n' "$(sanitize_component "$(repo_owner "$repo")")" "$(sanitize_component "$(repo_name "$repo")")"
}

host_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    *) return 1 ;;
  esac
}

make_runner_name() {
  local prefix="$1" repo="$2" name candidate hash
  name="$(sanitize_component "$(repo_name "$repo")")"
  candidate="$(sanitize_component "${prefix}-${name}")"
  if ((${#candidate} <= 60)); then
    printf '%s\n' "$candidate"
    return
  fi
  hash="$(printf '%s' "$repo" | sha256sum | cut -c1-8)"
  printf '%s-%s\n' "${candidate:0:51}" "$hash"
}

csv_normalize() {
  local raw="$1" item out=""
  IFS=',' read -r -a _items <<< "$raw"
  for item in "${_items[@]}"; do
    item="${item//[[:space:]]/}"
    [[ -n "$item" ]] || continue
    [[ "$item" =~ ^[A-Za-z0-9_.-]+$ ]] || die "Invalid label: $item"
    if [[ ",${out}," != *",${item},"* ]]; then
      out="${out:+${out},}${item}"
    fi
  done
  printf '%s\n' "$out"
}

strip_quotes() {
  local value="$1"
  if [[ ${#value} -ge 2 ]]; then
    if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]] || [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi
  printf '%s\n' "$value"
}

PARSED_REPO=""
PARSED_TOKEN=""
parse_configure_command() {
  local line="${1:-}" url="" token=""
  PARSED_REPO=""
  PARSED_TOKEN=""

  # Accept Markdown/chat escaped forms such as https\://github.com/owner/repo.
  line="${line//\\:/:}"

  if [[ "$line" =~ --url[[:space:]]+([^[:space:]]+) ]]; then
    url="$(strip_quotes "${BASH_REMATCH[1]}")"
  fi
  if [[ "$line" =~ --token[[:space:]]+([^[:space:]]+) ]]; then
    token="$(strip_quotes "${BASH_REMATCH[1]}")"
  fi

  [[ -n "$url" && -n "$token" ]] || return 1
  [[ "$url" == https://github.com/* ]] || return 1
  PARSED_REPO="$(normalize_repo "$url")" || return 1
  [[ "$token" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  PARSED_TOKEN="$token"
}

PARSED_REMOVE_TOKEN=""
parse_remove_command() {
  local line="${1:-}" token=""
  PARSED_REMOVE_TOKEN=""
  if [[ "$line" =~ --token[[:space:]]+([^[:space:]]+) ]]; then
    token="$(strip_quotes "${BASH_REMATCH[1]}")"
  elif [[ "$line" =~ ^[A-Za-z0-9_-]+$ ]]; then
    token="$line"
  fi
  [[ "$token" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  PARSED_REMOVE_TOKEN="$token"
}

validate_version() {
  [[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

resolve_runner_asset() {
  local arch="$1" requested_version="${2:-}" endpoint json
  if [[ -n "$requested_version" ]]; then
    validate_version "$requested_version" || die "Invalid runner version: $requested_version"
    endpoint="${SHRM_RUNNER_RELEASE_API}/tags/v${requested_version}"
  else
    endpoint="${SHRM_RUNNER_RELEASE_API}/latest"
  fi

  json="$(curl --fail --silent --show-error --location \
    -H 'Accept: application/vnd.github+json' \
    -H "X-GitHub-Api-Version: ${SHRM_GITHUB_API_VERSION}" \
    "$endpoint")" || die "Unable to resolve GitHub Actions runner release metadata."

  printf '%s' "$json" | python3 -c '
import json, sys
arch = sys.argv[1]
data = json.load(sys.stdin)
tag = data.get("tag_name", "")
version = tag[1:] if tag.startswith("v") else tag
name = f"actions-runner-linux-{arch}-{version}.tar.gz"
for asset in data.get("assets", []):
    if asset.get("name") == name:
        digest = asset.get("digest") or ""
        url = asset.get("browser_download_url") or ""
        if not digest.startswith("sha256:") or not url:
            raise SystemExit(3)
        print("\t".join((version, name, url, digest.split(":", 1)[1])))
        raise SystemExit(0)
raise SystemExit(2)
' "$arch" || die "GitHub release metadata did not contain a verified linux/${arch} runner asset."
}

load_config() {
  [[ -r "$SHRM_CONFIG_FILE" ]] || die "Manager is not initialized. Run: runner-manager init --profile xserver (or desktop-wsl)"
  # The config is root-owned and generated by runner-manager.
  # shellcheck disable=SC1090
  source "$SHRM_CONFIG_FILE"
  : "${RUNNER_USER:?RUNNER_USER missing from config}"
  : "${RUNNER_ROOT:?RUNNER_ROOT missing from config}"
  : "${RUNNER_NAME_PREFIX:?RUNNER_NAME_PREFIX missing from config}"
  : "${RUNNER_LABELS:?RUNNER_LABELS missing from config}"
  : "${SELECTOR_LABEL:?SELECTOR_LABEL missing from config}"
  : "${RUNNER_ARCH:?RUNNER_ARCH missing from config}"
  : "${RUNNER_CACHE:?RUNNER_CACHE missing from config}"
}

state_file_for_repo() {
  printf '%s/%s.conf\n' "$SHRM_STATE_DIR" "$(repo_key "$1")"
}

load_state() {
  local repo="$1" state
  state="$(state_file_for_repo "$repo")"
  [[ -r "$state" ]] || return 1
  # State files are root-owned and generated by runner-manager.
  # shellcheck disable=SC1090
  source "$state"
}

write_state() {
  local repo="$1" runner_name="$2" runner_dir="$3" labels="$4" version="$5" phase="${6:-managed}" state tmp
  state="$(state_file_for_repo "$repo")"
  tmp="$(mktemp)"
  {
    printf 'REPO=%q\n' "$repo"
    printf 'RUNNER_NAME=%q\n' "$runner_name"
    printf 'RUNNER_DIR=%q\n' "$runner_dir"
    printf 'RUNNER_LABELS_EFFECTIVE=%q\n' "$labels"
    printf 'RUNNER_VERSION=%q\n' "$version"
    printf 'RUNNER_PHASE=%q\n' "$phase"
    printf 'CREATED_AT=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$tmp"
  sudo install -d -m 0755 "$SHRM_STATE_DIR"
  sudo install -o root -g root -m 0644 "$tmp" "$state"
  rm -f "$tmp"
}

remove_state() {
  sudo rm -f "$(state_file_for_repo "$1")"
}

service_name_from_dir() {
  local dir="$1"
  if [[ -r "$dir/.service" ]]; then
    cat "$dir/.service"
  fi
}

run_as_runner() {
  local user="$1" dir="$2"
  shift 2
  sudo -u "$user" -H bash -c 'cd "$1"; shift; exec "$@"' bash "$dir" "$@"
}

confirm() {
  local prompt="$1"
  [[ "${SHRM_ASSUME_YES:-0}" == "1" ]] && return 0
  read -r -p "${prompt} [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}
