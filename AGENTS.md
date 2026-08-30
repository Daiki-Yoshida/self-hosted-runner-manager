# Agent Guidance

## Purpose

Manage repository-scoped GitHub Actions self-hosted runners on trusted Linux hosts without storing long-lived GitHub credentials on those hosts.

## Safety invariants

- Never require `gh auth`, PAT, OAuth token, or GitHub SSH credentials on runner hosts.
- Never persist or print runner registration/removal tokens.
- Never execute pasted GitHub setup blocks. Parse them as untrusted data only.
- Validate expected repository against Configure URL before registration when an expected repo is supplied.
- Use GitHub UI setup metadata only to identify rollout version/expected values; use public official `actions/runner` release metadata for actual URL/digest.
- Verify SHA-256 before extracting or caching runner packages.
- Runner process must not run as root.
- Use dedicated `gha-runner` user; do not add it to sudo/docker/privileged groups without a separate reviewed change.
- Keep systemd integration aligned with upstream `svc.sh`.
- Do not modify SSH, UFW, provider firewalls, Tailscale, or unrelated host configuration.
- Preserve diagnostic state after remote registration if later service setup fails.

## Scope

- Linux/systemd only.
- Repository-scoped runners only.
- One runner process/service per repository per host.
- Host-wide cross-repository concurrency limiting is not implemented yet.

## Verification

```bash
bash -n bin/runner-manager lib/common.sh bootstrap.sh install.sh uninstall.sh tests/run.sh
tests/run.sh
```
