# Security Model

## Trust boundary

A self-hosted runner executes workflow code on the host. A repository that can dispatch code to a runner must therefore be treated as trusted for that host's runner privileges.

This project is designed for trusted private repositories owned by the operator. Public or untrusted-contributor repositories should not be attached to these persistent hosts without a separate threat model.

## Privilege separation

The administrator runs `runner-manager` as a normal sudo-capable account. The manager creates and uses a dedicated account:

```text
gha-runner
```

The account is not granted sudo by this project. It is also not added to the Docker group by this project. Granting Docker socket access would be a separate security decision because it is effectively host-privileged in common Docker configurations.

## GitHub authentication

The manager relies on `gh auth` owned by the administrator. GitHub's repository runner endpoints require repository administration permissions. For classic OAuth/PAT access to private repositories, GitHub documents the `repo` scope; fine-grained tokens require repository Administration permissions (read for download metadata and write for registration/removal tokens).

The long-running runner account does not receive the administrator's `gh` credentials.

## Registration and removal tokens

GitHub's registration and removal tokens expire after one hour. The manager:

- requests them only when needed;
- stores them only in shell variables;
- does not write them into manager state;
- does not intentionally print them;
- clears the shell variable immediately after the configuration/removal call.

The official `config.sh` requires the token as an argument, so the short-lived token may be briefly observable to a sufficiently privileged local process through process inspection. This is a limitation of the upstream interface, not a persistent secret created by the manager.

## Runner package integrity

The manager obtains the download URL from GitHub's authenticated runner-download API and downloads it over HTTPS from GitHub. The REST response currently provides filename and download URL but no checksum field. The GitHub web setup flow may display a checksum, but v1 does not scrape UI content to reproduce that check.

This tradeoff is explicit. A future version may add an independent release-integrity mechanism if GitHub exposes a stable machine-readable checksum source.

## Network policy

This project does not modify:

- UFW;
- XServer packet filters;
- SSH;
- Tailscale;
- inbound ports.

GitHub Actions runner communication is outbound. Network hardening remains a host-operations responsibility.

## systemd and needrestart

The manager uses GitHub's generated `svc.sh` for systemd integration. During `init`, Debian/Ubuntu hosts with `needrestart` receive GitHub's documented override preventing an Actions runner service from being restarted in the middle of a workflow job.
