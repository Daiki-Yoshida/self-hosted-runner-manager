# Security Model

## Trust boundary

A self-hosted runner executes workflow code on the host. A repository that can dispatch code to a runner must be trusted for that host's runner privileges.

This project is intended for trusted private repositories owned by the operator. Public repositories or untrusted contributor workflows need a separate threat model.

## No long-lived GitHub credential on runner hosts

The core v0.2 rule is:

> Runner hosts do not need `gh auth`, PATs, OAuth tokens, or GitHub App credentials.

Repository authentication stays in the human's browser session.

For registration, the operator copies GitHub's short-lived command:

```text
./config.sh --url https://github.com/OWNER/REPO --token ********
```

into a hidden `runner-manager add` prompt.

For removal, the same model is used with GitHub's short-lived removal command/token.

## Token handling

The manager:

- does not evaluate pasted Configure/Remove text as shell code;
- extracts only validated URL/token fields;
- disables terminal echo while the line is pasted;
- never writes registration/removal tokens to manager config/state;
- never intentionally prints tokens;
- clears shell variables after use.

The upstream `config.sh` interface requires the token as a command-line argument. Therefore a sufficiently privileged local process can briefly observe that short-lived token in process arguments. This is an upstream interface limitation.

## Privilege separation

The administrator runs `runner-manager` as a normal sudo-capable account. Runner processes run as:

```text
gha-runner
```

This project does not grant `gha-runner`:

- sudo;
- Docker group membership;
- admin-user SSH credentials;
- GitHub API credentials.

Docker socket access is intentionally separate because normal Docker daemon access is commonly equivalent to host-level privilege.

## Runner package source and integrity

Package metadata is obtained from GitHub's public `actions/runner` release API over HTTPS without authentication.

The manager selects the expected Linux/architecture asset and requires GitHub release asset metadata to include:

```text
sha256:<digest>
```

The downloaded archive is checked with `sha256sum` before extraction or caching. Cached archives are revalidated before reuse.

The manager fails closed if the selected release asset does not contain a SHA-256 digest.

## Progressive runner releases

GitHub Actions Runner uses progressive rollout. The newest public `actions/runner` release may briefly differ from the version shown by one repository's authenticated setup page.

Because the host intentionally cannot query that private page, v0.2 uses:

```bash
runner-manager add
```

for public latest and supports:

```bash
runner-manager add --version X.Y.Z
```

when the repository page displays a different version. URL and digest are still independently resolved from official public release metadata.

This limitation is preferable to introducing persistent GitHub credentials onto the runner host.

## Public manager repository

For credential-free installation, this manager repository should be public. No secrets, tokens, host addresses, or private repository data should ever be committed here.

A public source repository also makes the code executed with sudo reviewable before installation. Operators should prefer a pinned tag/commit for mature deployments rather than blindly piping a mutable branch directly into a privileged shell.

## Network policy

This project does not modify:

- UFW;
- XServer packet filters;
- SSH;
- Tailscale;
- inbound ports.

GitHub Actions runner communication is outbound. Network hardening remains a host-operations responsibility.

## systemd and needrestart

The manager uses GitHub's generated `svc.sh` for systemd integration. During `init`, Debian/Ubuntu hosts with `needrestart` receive GitHub's documented override preventing Actions runner services from being restarted in the middle of workflow jobs.

## Local state exposure

Manager config and per-repository state contain repository names, runner names, versions, paths, labels, and timestamps only. They are root-owned and do not contain GitHub registration/removal tokens.
