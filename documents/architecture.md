# Architecture

## Goal

Repository-scoped GitHub Actions self-hosted runner を、長期 GitHub credential を runner host に置かずに反復可能な形で管理する。

## Trust split

```text
Browser / operator
  GitHub login exists here
  |
  | short-lived GitHub setup text
  v
Runner host
  no gh auth / PAT / OAuth / GitHub SSH key
```

GitHub private-repository API を runner host から呼ばない代わりに、New self-hosted runner UI の setup block を operator が一度 pasteする。

## Add flow (v0.3)

1. Optional `OWNER/REPO` argument を expected repository として保持する。
2. GitHub Download + Configure block を hidden multi-line input で受け取る。
3. Pasted text は shell として実行せず、parser が data として以下だけ抽出する。
   - Configure repository URL
   - short-lived registration token
   - Linux runner version / architecture
   - official release filename / download URL
   - SHA-256 (存在する場合)
4. Expected repository と Configure URL を比較する。
5. GitHub UI から version を抽出できた場合、それを progressive-rollout source of truth とする。
6. Public `actions/runner` Release API の exact tag (`vX.Y.Z`) を取得する。
7. Official release metadata と pasted filename / URL / digest を cross-check する。
8. Actual download URL / SHA-256 は official public release metadata を使用する。
9. Versioned cache を検証し、必要なら package をdownloadする。
10. Dedicated `gha-runner` user で official `config.sh --unattended` を実行する。
11. Official `svc.sh` で systemd service を install/start する。
12. Non-secret local state を保存する。

Configure line だけをpasteした場合は public latest へfallbackするが、progressive rollout の差を自動検出できないため警告する。

## Why pasted shell is never executed

Setup page 由来の text は untrusted input として扱う。manager は `eval`, `source`, pasted `bash -c` を使用しない。

Extra command が含まれていても parser が必要 field を抽出するだけで実行されない。

## Host profiles

### xserver

- `personal-ci`
- `xserver`
- `always-on`

### desktop-wsl

- `personal-ci`
- `desktop-wsl`
- `high-memory`

## Runtime

```text
/opt/github-actions-runners/<owner>--<repo>/
```

One repository runner = one runner process = one systemd service.

## Concurrency

Cross-repository host-wide concurrency is not enforced in v0.3. Multiple repository-scoped runner processes can accept jobs concurrently.

A future design should use a robust host-wide admission mechanism that handles abnormal exits and stale locks before being enabled by default.
