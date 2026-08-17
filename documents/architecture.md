# Architecture

## Goal

`self-hosted-runner-manager` removes the repetitive GitHub UI workflow required to add repository-scoped self-hosted runners. A host administrator supplies only the repository identifier:

```bash
runner-manager add Daiki-Yoshida/TestGitHubActions
```

The manager uses the already-authenticated GitHub CLI to perform the repository-specific work.

## Runtime model

Each physical host has one manager configuration and zero or more repository runner installations.

```text
Host
├─ admin user
│  └─ runner-manager + gh authentication
├─ gha-runner user
│  ├─ /opt/github-actions-runners/owner--repo-a
│  └─ /opt/github-actions-runners/owner--repo-b
└─ systemd
   ├─ actions.runner....repo-a.service
   └─ actions.runner....repo-b.service
```

`gh` credentials belong to the human/admin account. The long-running runner service does not need those credentials.

## Provisioning flow

`runner-manager add OWNER/REPO` performs:

1. Validate Linux, systemd, manager configuration, and GitHub CLI authentication.
2. Verify that the authenticated GitHub account has repository admin access.
3. Query `GET /repos/{owner}/{repo}/actions/runners/downloads` through `gh api` and select the current Linux package for the host architecture.
4. Reuse a versioned archive from `/var/cache/self-hosted-runner-manager/`, or download it once when missing, then extract into a repository-specific directory.
5. Request a one-hour registration token with `POST /repos/{owner}/{repo}/actions/runners/registration-token`.
6. Run the official `config.sh` non-interactively as `gha-runner` with host-specific labels.
7. Install and start the runner through the generated `svc.sh` systemd integration.
8. Save non-secret local state under `/etc/self-hosted-runner-manager/runners/`.
9. Verify that GitHub reports the named runner.

## Host profiles

### `xserver`

Default custom labels:

- `personal-ci`
- `xserver`
- `always-on`

Suggested workflow selector:

```yaml
runs-on: [self-hosted, xserver]
```

### `desktop-wsl`

Default custom labels:

- `personal-ci`
- `desktop-wsl`
- `high-memory`

Suggested workflow selector:

```yaml
runs-on: [self-hosted, desktop-wsl]
```

A workflow that may run on either host can select the shared label:

```yaml
runs-on: [self-hosted, personal-ci]
```

When both matching runners are online and idle, GitHub chooses an eligible runner; this is not a priority/fallback mechanism.

## Concurrency

Repository-scoped runners are independent runner processes. If five repositories are registered on one host, up to five jobs can be accepted concurrently.

This is particularly important for the 4-core / 6-GB VPS target. v1 deliberately does **not** claim to enforce a host-wide concurrency limit. Heavy workflows should initially use explicit labels and operational discipline while a robust host-wide semaphore design is evaluated.

A future implementation must handle abnormal runner exits without leaving a stale lock before it can safely become a default.

## State

Host configuration:

```text
/etc/self-hosted-runner-manager/config
```

Per-repository non-secret state:

```text
/etc/self-hosted-runner-manager/runners/<owner>--<repo>.conf
```

Runner runtime directories:

```text
/opt/github-actions-runners/<owner>--<repo>/
```

Registration/removal tokens are never written to these files.
