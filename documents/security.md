# Security Model

## Primary goal

Runner host に long-lived GitHub credential を置かない。

Not required:

- GitHub CLI authentication
- PAT
- OAuth token
- GitHub SSH key

The browser/operator remains the authenticated GitHub boundary.

## Short-lived token handling

Registration/removal tokens are accepted through hidden input, never written to manager state, and cleared after use.

Upstream `config.sh` requires the token as argv, so a sufficiently privileged local process may observe it briefly during execution. The token is short-lived and is not made persistent by this project.

## Pasted setup block handling

Pasted GitHub setup text is **never executed directly**.

The parser only recognizes constrained fields:

- `https://github.com/OWNER/REPO`
- registration token syntax
- `actions-runner-linux-(x64|arm64)-X.Y.Z.tar.gz`
- official `github.com/actions/runner/releases/download/...` URL
- 64-hex SHA-256

Any other pasted command is ignored as data. The implementation does not `eval` or `source` the setup block.

When `runner-manager add OWNER/REPO` is used, the Configure URL must match that repository (case-insensitive) before registration.

## Runner package integrity

The GitHub UI block determines the repository rollout version when available. The manager then requests that exact public `actions/runner` release and uses official release asset metadata for the actual download URL and `sha256:` digest.

If the UI supplied filename / URL / SHA-256, those values must match public official metadata. A mismatch aborts before registration.

Cached archives are revalidated before reuse.

## Privilege separation

Runner services execute as dedicated `gha-runner` Unix user.

This project does not add `gha-runner` to:

- sudo
- docker
- other privilege-bearing groups

`runner-manager` itself is run by the normal sudo-capable administrator and uses sudo only for host installation/service operations.

## Network boundary

The project does not change SSH, UFW, cloud packet filters, Tailscale, or inbound ports. GitHub Actions runner communication is outbound.

## Repository trust

A self-hosted runner executes workflow code. Only repositories trusted to execute code with the runner user's host permissions should target these persistent runners. Public/untrusted-fork workflow execution requires a separate threat model.
