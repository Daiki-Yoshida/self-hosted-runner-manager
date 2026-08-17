# Architecture

## Goal

`self-hosted-runner-manager` manages many repository-scoped GitHub Actions self-hosted runners without storing long-lived GitHub credentials on the runner host.

The operator performs the repository-authenticated step in a normal browser and pastes only GitHub's short-lived Configure command:

```text
./config.sh --url https://github.com/OWNER/REPO --token ********
```

Everything else is host-local automation.

## Runtime model

```text
Browser / human GitHub session
  |
  | short-lived repository registration token
  v
Host admin user
  └─ runner-manager
      ├─ unauthenticated public API -> actions/runner releases
      ├─ SHA-256 verify official runner archive
      └─ sudo only for host setup / service lifecycle

Host
├─ admin user
│  └─ runner-manager (no gh auth / no PAT)
├─ gha-runner user
│  ├─ /opt/github-actions-runners/owner--repo-a
│  └─ /opt/github-actions-runners/owner--repo-b
└─ systemd
   ├─ actions.runner....repo-a.service
   └─ actions.runner....repo-b.service
```

The long-running `gha-runner` user never receives GitHub API credentials from this project.

## Provisioning flow

`runner-manager add` performs:

1. Validate Linux, systemd, host configuration, and required local tools.
2. Prompt (hidden input) for the exact `./config.sh --url ... --token ...` line shown by GitHub.
3. Parse and validate repository URL and short-lived registration token without evaluating the input as shell code.
4. Resolve the public `actions/runner` latest release, or a user-selected `--version X.Y.Z` release.
5. Select the exact `actions-runner-linux-<arch>-<version>.tar.gz` asset.
6. Require the release asset's machine-readable `sha256:` digest.
7. Reuse a verified versioned archive from `/var/cache/self-hosted-runner-manager/`, or download and verify it.
8. Extract into a repository-specific runner directory.
9. Run official `config.sh` as `gha-runner` with host-specific labels.
10. Persist only non-secret local state.
11. Install/start the official runner systemd integration through generated `svc.sh`.
12. Verify local systemd active state.

## Why the manager does not automatically query the private repository setup page

GitHub's repository runner setup page is authenticated and repository-specific. The host intentionally has no GitHub login credential, so it cannot safely query that private page or the private repository runner APIs.

The public `actions/runner` release API is sufficient to obtain:

- release version;
- Linux asset URL;
- SHA-256 digest.

However, GitHub uses progressive runner releases. The newest public runner release can temporarily differ from the version shown for a specific repository. For that reason:

```bash
runner-manager add
```

uses the latest public stable release, while:

```bash
runner-manager add --version 2.336.0
```

lets the operator mirror the version shown by the repository setup page without manually copying download URLs or hashes.

## Failure semantics

Before `config.sh` succeeds, failed provisioning removes partial local runtime state.

After `config.sh` succeeds, the runner exists remotely. If subsequent service installation/start fails, the manager deliberately preserves the local runner directory and local state instead of deleting it and stranding an unmanaged remote registration.

## Host profiles

### `xserver`

- `personal-ci`
- `xserver`
- `always-on`

```yaml
runs-on: [self-hosted, xserver]
```

### `desktop-wsl`

- `personal-ci`
- `desktop-wsl`
- `high-memory`

```yaml
runs-on: [self-hosted, desktop-wsl]
```

Shared pool:

```yaml
runs-on: [self-hosted, personal-ci]
```

This is eligibility routing, not priority/fallback routing.

## Status model

Without host GitHub credentials, `runner-manager status` reports local manager state and systemd status only. GitHub's remote online/busy state remains visible in the repository Actions Runner UI.

## Removal flow

Removal also avoids long-lived credentials:

1. Operator opens the registered runner's GitHub removal UI.
2. GitHub provides a short-lived `./config.sh remove --token ...` command.
3. Operator pastes it into a hidden manager prompt.
4. Manager stops the service, invokes official `config.sh remove`, uninstalls systemd integration, then removes local state.
5. If upstream removal fails, manager attempts to restart the existing service instead of blindly deleting local state.

## Concurrency

Repository-scoped runners are independent processes. Five registered repositories can accept five jobs simultaneously.

This is important for the 4-core / 6-GB VPS target. v0.2 does not claim to enforce a host-wide concurrency limit. A robust cross-runner semaphore remains a separate design task.

## State

Host config:

```text
/etc/self-hosted-runner-manager/config
```

Non-secret per-repository state:

```text
/etc/self-hosted-runner-manager/runners/<owner>--<repo>.conf
```

Runtime:

```text
/opt/github-actions-runners/<owner>--<repo>/
```

Cache:

```text
/var/cache/self-hosted-runner-manager/
```

Registration/removal tokens are never written to manager state.
