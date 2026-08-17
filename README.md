# self-hosted-runner-manager

Repository-scoped GitHub Actions self-hosted runnersを、GitHub UIで毎回 `Download` / `Configure` する代わりに **GitHub CLI (`gh`) から自動構築・管理するLinux向けツール**です。

主な想定ホスト:

- 常時稼働のUbuntu VPS
- Windows上のWSL Ubuntu

Organization runnerを前提にせず、個人アカウント配下に多数あるprivate repositoryへrepository-level runnerを追加する運用を簡略化します。

## 目標UX

GitHubの `Settings -> Actions -> Runners -> New self-hosted runner` を開く必要はありません。

```bash
runner-manager add Daiki-Yoshida/TestGitHubActions
```

これだけで、managerが `gh api` を使って以下を実行します。

1. 対象repositoryへのadmin access確認
2. GitHub APIから現在のLinux runner download URL取得
3. runner packageをversioned cacheへdownload（既存なら再利用）/ 展開
4. 1時間有効のregistration tokenをGitHub APIから取得
5. 専用Unix user `gha-runner` として `config.sh` 実行
6. host profileに応じたrunner name / labels設定
7. GitHub公式 `svc.sh` でsystemd service化
8. service起動
9. GitHub APIから登録結果確認

registration tokenを人間がコピーする必要はありません。

## 前提

v1は以下を前提にします。

- Linux
- systemd
- `sudo`
- `curl`
- `tar`
- GitHub CLI `gh`
- `gh auth login` 済み
- 対象repositoryのadmin権限

GitHub CLIには専用の `runner add` コマンドはないため、このツールは `gh api` からGitHub Actions Self-hosted Runners REST APIを利用します。

private repositoryでclassic OAuth/PATを利用する場合、GitHubのrunner registration/remove APIには `repo` scopeが必要です。権限不足の場合は利用している認証方式を確認してください。

## Install

```bash
git clone https://github.com/Daiki-Yoshida/self-hosted-runner-manager.git
cd self-hosted-runner-manager
./install.sh
```

インストール先:

```text
/usr/local/bin/runner-manager
/usr/local/lib/self-hosted-runner-manager/
```

## 1. Host initialization

ホストごとに一度だけ実行します。

### XServer VPS

```bash
runner-manager init --profile xserver
```

Default custom labels:

```text
personal-ci
xserver
always-on
```

### Desktop WSL

```bash
runner-manager init --profile desktop-wsl
```

Default custom labels:

```text
personal-ci
desktop-wsl
high-memory
```

`init` はrunner runtime用の専用ユーザー `gha-runner` を作成します。runnerをrootや普段のadmin accountでは実行しません。

状態確認:

```bash
runner-manager doctor
```

## 2. Add a repository runner

```bash
runner-manager add Daiki-Yoshida/TestGitHubActions
```

URLでも指定できます。

```bash
runner-manager add https://github.com/Daiki-Yoshida/TestGitHubActions
```

XServer profileなら概ね以下のようなrunnerになります。

```text
Runner name:
  xserver-testgithubactions

Labels:
  self-hosted
  Linux
  X64
  personal-ci
  xserver
  always-on
```

runner runtimeはrepositoryごとに分離されます。同じrunner versionのarchiveは `/var/cache/self-hosted-runner-manager/` で再利用されるため、repository追加のたびに同じpackageを再downloadしません。

```text
/opt/github-actions-runners/
├── daiki-yoshida--testgithubactions/
├── daiki-yoshida--money-mira/
└── ...
```

## 3. Use in workflow

XServerを明示:

```yaml
runs-on: [self-hosted, xserver]
```

Desktop WSLを明示:

```yaml
runs-on: [self-hosted, desktop-wsl]
```

どちらでもよい処理:

```yaml
runs-on: [self-hosted, personal-ci]
```

`personal-ci` で複数runnerがonline + idleの場合、GitHubが条件に合うrunnerを選択します。`desktop-wsl` 優先・不在時だけ `xserver` のようなpriority/fallback指定ではありません。

## Status

一覧:

```bash
runner-manager list
```

ローカルsystemd状態とGitHub側状態を確認:

```bash
runner-manager status
```

1 repositoryのみ:

```bash
runner-manager status Daiki-Yoshida/TestGitHubActions
```

## Remove

```bash
runner-manager remove Daiki-Yoshida/TestGitHubActions
```

managerはGitHub APIから1時間有効のremove tokenをその場で取得し、service停止 -> service削除 -> `config.sh remove` -> runtime削除まで行います。

確認なし:

```bash
runner-manager remove Daiki-Yoshida/TestGitHubActions --yes
```

## Token handling

registration/remove tokenは:

- GitHub REST APIから必要時だけ取得
- manager stateへ保存しない
- 意図的にstdout/stderrへ表示しない
- `config.sh` / `config.sh remove` 実行後にshell variableから破棄

GitHubのこれらのtoken自体も1時間で失効します。

詳細は [documents/security.md](documents/security.md) を参照してください。

## Important: concurrency

repository-level runnerはrepositoryごとに独立したrunner processです。

例えばVPSに5 repositoryを登録すると、5 runnerが同時にjobを受け取る可能性があります。

**v1はhost-wideの最大同時job数を強制しません。**

4 Core / 6GB RAMのVPSでは特に注意してください。まずは軽量CIを `xserver` に割り当て、重いjobは `desktop-wsl` へ寄せる運用を推奨します。

この問題は [documents/architecture.md](documents/architecture.md) に明示しています。

## What this project intentionally does not change

managerは以下を触りません。

- UFW
- XServer packet filter
- SSH
- Tailscale
- inbound ports
- Docker group membership
- sudoers

Self-hosted runnerのために新しいinbound portを開放することもありません。

## Development

```bash
bash -n bin/runner-manager lib/common.sh install.sh uninstall.sh tests/run.sh
tests/run.sh
```

GitHub Actionsのproject自身のCIはGitHub-hosted `ubuntu-latest` を使用します。

## Documents

- [Architecture](documents/architecture.md)
- [Security model](documents/security.md)

## References

- GitHub REST API: Self-hosted runners
  - https://docs.github.com/en/rest/actions/self-hosted-runners
- GitHub CLI `gh api`
  - https://cli.github.com/manual/gh_api
- Configure self-hosted runner as a service
  - https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/configure-the-application
