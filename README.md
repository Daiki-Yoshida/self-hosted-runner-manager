# self-hosted-runner-manager

Repository-scoped GitHub Actions self-hosted runner を、多数の private repository へ安全かつ少ない手入力で追加する Linux 向け管理ツールです。

**Runner ホストには `gh` / PAT / OAuth token / GitHub SSH key を置きません。**

GitHub のブラウザ画面に表示される短時間有効な setup block を一度 paste すると、manager が必要な情報だけを解析して runner を構築します。貼り付けられた shell command 自体は **一切 `eval` / `bash -c` しません**。

## Target UX

```bash
runner-manager add Daiki-Yoshida/TestGitHubActions
```

manager が対象 repository の New self-hosted runner URL を表示します。

GitHub の `Download` + `Configure` をまとめてコピーして terminal に一度 pasteし、最後に `Ctrl-D`:

```text
mkdir actions-runner && cd actions-runner
curl -o actions-runner-linux-x64-2.337.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.337.0/actions-runner-linux-x64-2.337.0.tar.gz
echo "<sha256>  actions-runner-linux-x64-2.337.0.tar.gz" | shasum -a 256 -c
tar xzf ./actions-runner-linux-x64-2.337.0.tar.gz
./config.sh --url https://github.com/Daiki-Yoshida/TestGitHubActions --token ********
```

これだけで manager が:

1. Configure URL から repository を検証
2. GitHub setup block から rollout 対象 runner version / architecture を自動認識
3. public `actions/runner` Release API から同じ version の official asset を取得
4. pasted download URL / filename / SHA-256 が official metadata と一致する場合だけ続行
5. package download + SHA-256 検証 + cache
6. dedicated `gha-runner` user で `config.sh` 実行
7. host profile labels を付与
8. GitHub 公式 `svc.sh` で systemd service 化
9. local state を保存

します。

## Why paste the whole setup block?

GitHub Actions Runner は progressive rollout です。public latest と、特定 repository の `New self-hosted runner` 画面に表示される version が一時的に異なることがあります。

v0.3 では **GitHub UI に表示された Download block の version を自動で採用**するため、通常は `--version` を手入力する必要がありません。

Download block がない Configure line だけでも登録できます。その場合は public latest に fallback し、警告を表示します。

緊急時や検証用には明示指定も残しています。

```bash
runner-manager add Daiki-Yoshida/TestGitHubActions --version 2.337.0
```

## Security model

```text
Browser (GitHub authenticated)
  |
  | short-lived setup text
  v
runner-manager on VPS / WSL
  |
  +-- parse only; never execute pasted shell
  +-- public actions/runner Release API (no auth)
  +-- official package + SHA-256 digest
  +-- config.sh as gha-runner
  +-- systemd

No long-lived GitHub credential on runner host.
```

Registration/remove token は:

- hidden input で受け取る
- manager state へ保存しない
- stdout/stderr へ表示しない
- `config.sh` に渡した後に shell variable から破棄する

upstream `config.sh` の仕様上、実行中だけ同一ホスト上の高権限 process から argv を観測できる可能性はあります。

## Install

credential-free bootstrap を使うには、この repository を public で運用してください。

まず内容を保存・確認してから実行する運用を推奨します。

```bash
curl -fsSL \
  https://raw.githubusercontent.com/Daiki-Yoshida/self-hosted-runner-manager/main/bootstrap.sh \
  -o /tmp/self-hosted-runner-manager-bootstrap.sh

less /tmp/self-hosted-runner-manager-bootstrap.sh
bash /tmp/self-hosted-runner-manager-bootstrap.sh
```

`bootstrap.sh` は public GitHub Release が存在すれば **latest stable tag** を優先します。Release がまだない場合だけ `main` に fallback して警告します。

固定 version:

```bash
SHRM_VERSION=0.3.0 bash /tmp/self-hosted-runner-manager-bootstrap.sh
```

任意 tag / commit pin:

```bash
SHRM_REF=<tag-or-commit> bash /tmp/self-hosted-runner-manager-bootstrap.sh
```

Clone install も可能です。

```bash
git clone https://github.com/Daiki-Yoshida/self-hosted-runner-manager.git
cd self-hosted-runner-manager
./install.sh
```

Required commands:

- `curl`
- `tar`
- `sha256sum`
- `python3`
- `sudo`
- `systemd`

`gh` は不要です。

## Initialize host

### XServer VPS

```bash
runner-manager init --profile xserver
runner-manager doctor
```

Labels:

```text
personal-ci
xserver
always-on
```

### Desktop WSL

```bash
runner-manager init --profile desktop-wsl
runner-manager doctor
```

Labels:

```text
personal-ci
desktop-wsl
high-memory
```

`init` は dedicated Unix user `gha-runner`、runtime/cache/state directories、Ubuntu `needrestart` override を準備します。`gha-runner` に sudo / Docker group は与えません。

## Add runner

Repository を先に指定する推奨形:

```bash
runner-manager add Daiki-Yoshida/TestGitHubActions
```

この場合、pasted Configure line が別 repository を指していれば **登録前に拒否**します。

Repository 名を省略して setup block の Configure URL から自動判定することもできます。

```bash
runner-manager add
```

## Workflow selectors

VPS only:

```yaml
runs-on: [self-hosted, xserver]
```

Desktop WSL only:

```yaml
runs-on: [self-hosted, desktop-wsl]
```

Either host:

```yaml
runs-on: [self-hosted, personal-ci]
```

`personal-ci` は priority/fallback ではありません。

## Status

```bash
runner-manager list
runner-manager status
runner-manager status Daiki-Yoshida/TestGitHubActions
```

Runner host に private-repo credential を置かないため、status は local systemd/state を表示します。GitHub remote status はブラウザで確認します。

## Remove

```bash
runner-manager remove Daiki-Yoshida/TestGitHubActions
```

GitHub の runner removal 画面に表示される:

```text
./config.sh remove --token ********
```

だけを hidden prompt へ pasteします。remove token も保存しません。

## State

```text
/etc/self-hosted-runner-manager/config
/etc/self-hosted-runner-manager/runners/<owner>--<repo>.conf
/opt/github-actions-runners/<owner>--<repo>/
/var/cache/self-hosted-runner-manager/
```

state は non-secret のみです。

## Concurrency limitation

Repository-level runner は repository ごとに独立 process です。1台に10 repositoryを登録すれば、理論上10 jobを同時acceptできます。

**v0.3 は host-wide concurrency limit をまだ実装していません。** 4-core / 6-GB VPS では特に軽量 workflow に限定するか、別途 concurrency 制御を設計してください。

## Development

```bash
bash -n bin/runner-manager lib/common.sh bootstrap.sh install.sh uninstall.sh tests/run.sh
tests/run.sh
```

詳細:

- [Architecture](documents/architecture.md)
- [Security model](documents/security.md)
