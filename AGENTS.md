# Agent Guidance

## Purpose

This repository manages repository-scoped GitHub Actions self-hosted runners on trusted Linux hosts through GitHub CLI (`gh`) and the official GitHub Actions runner package.

## Safety invariants

- Never persist GitHub runner registration or removal tokens.
- Never print runner registration or removal tokens.
- The runner process must not run as root.
- Use a dedicated `gha-runner` Unix account for runner services.
- Do not add the runner account to `sudo`, `docker`, or other privilege-bearing groups unless a separate reviewed change explicitly requires it.
- Do not modify SSH, UFW, cloud-provider firewalls, Tailscale, or unrelated host configuration.
- Repository input must be validated and shell-quoted.
- `gh api` is the source for repository-scoped runner download metadata and short-lived registration/removal tokens.
- Keep systemd service installation aligned with GitHub's generated `svc.sh` rather than hand-authoring runner units.
- Preserve rollback: failed registration must not leave a registered but unmanaged runner when cleanup is possible.

## Scope

- Linux only.
- systemd is required in v1, including WSL environments.
- Repository-scoped runners only in v1.
- One runner service per repository per host.
- Host-wide cross-repository concurrency limiting is intentionally not implemented in v1; see `documents/architecture.md`.

## Verification

Before committing changes:

```bash
bash -n bin/runner-manager lib/common.sh install.sh uninstall.sh tests/run.sh
tests/run.sh
```
