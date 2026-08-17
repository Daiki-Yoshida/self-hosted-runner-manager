# Agent Guidance

## Purpose

This repository manages repository-scoped GitHub Actions self-hosted runners on trusted Linux hosts while avoiding long-lived GitHub credentials on those hosts.

## Safety invariants

- Never require `gh auth`, PATs, OAuth tokens, or GitHub App credentials on runner hosts.
- Registration/removal authentication is supplied only through short-lived GitHub-generated commands/tokens pasted interactively by the operator.
- Never persist or print runner registration/removal tokens.
- Never `eval` pasted Configure/Remove commands. Parse only expected URL/token fields and validate them.
- The runner process must not run as root.
- Use dedicated `gha-runner` Unix account for runner services.
- Do not add `gha-runner` to `sudo`, `docker`, or other privilege-bearing groups unless a separate reviewed change explicitly requires it.
- Do not modify SSH, UFW, cloud-provider firewalls, Tailscale, or unrelated host configuration.
- Runner packages must come from official public `actions/runner` release assets and must pass SHA-256 digest validation before extraction.
- Keep systemd service installation aligned with GitHub's generated `svc.sh` rather than hand-authoring runner units.
- After successful `config.sh`, do not delete local runner state on later failures; preserve recovery ability for the already-registered remote runner.

## Version selection

GitHub progressively rolls out runner versions. Default behavior may resolve the public latest stable release, but the CLI must retain an explicit `--version X.Y.Z` override so operators can match the version shown by a repository's authenticated setup page without introducing GitHub API credentials on the host.

## Scope

- Linux only.
- systemd required in v0.2, including WSL environments.
- Repository-scoped runners only.
- One runner service per repository per host.
- Host-wide cross-repository concurrency limiting is intentionally not implemented yet; see `documents/architecture.md`.

## Verification

Before committing changes:

```bash
bash -n bin/runner-manager lib/common.sh install.sh uninstall.sh tests/run.sh
tests/run.sh
```

Tests must not require GitHub authentication or live private-repository access.
