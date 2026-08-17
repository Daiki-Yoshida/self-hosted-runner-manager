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
  else
    printf 'PASS %s\n' "$label"
  fi
}

assert_eq 'Daiki-Yoshida/TestGitHubActions' "$(normalize_repo 'https://github.com/Daiki-Yoshida/TestGitHubActions')" 'normalize URL'
assert_eq 'Daiki-Yoshida/TestGitHubActions' "$(normalize_repo 'Daiki-Yoshida/TestGitHubActions.git')" 'normalize owner/repo'
assert_eq 'daiki-yoshida--testgithubactions' "$(repo_key 'Daiki-Yoshida/TestGitHubActions')" 'repo key'
assert_eq 'x64' "$(SHRM_TEST_UNAME_M=x86_64; uname() { if [[ "$1" == '-m' ]]; then printf '%s\n' "$SHRM_TEST_UNAME_M"; else command uname "$@"; fi; }; host_arch)" 'x64 mapping'
assert_eq 'personal-ci,xserver,always-on' "$(csv_normalize 'personal-ci, xserver,always-on,personal-ci')" 'label normalization'
assert_eq 'xserver-testgithubactions' "$(make_runner_name xserver 'Daiki-Yoshida/TestGitHubActions')" 'runner name'

long_repo='Daiki-Yoshida/this-is-an-extremely-long-repository-name-that-needs-a-shortened-runner-name-for-safety'
long_name="$(make_runner_name desktop-wsl "$long_repo")"
if ((${#long_name} > 60)); then
  printf 'FAIL runner name max length: %s (%d)\n' "$long_name" "${#long_name}" >&2
  failures=$((failures + 1))
else
  printf 'PASS runner name max length\n'
fi

if normalize_repo 'not a repo' >/dev/null 2>&1; then
  printf 'FAIL invalid repository rejected\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS invalid repository rejected\n'
fi

if ((failures)); then
  printf '%d test(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'All tests passed.\n'
