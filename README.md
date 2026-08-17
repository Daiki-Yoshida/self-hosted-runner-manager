# self-hosted-runner-manager

Repository-scoped GitHub Actions self-hosted runnerを、多数のprivate repositoryへ追加する作業を簡略化するLinux向け管理ツールです。

**v0.2から、RunnerホストにGitHub CLI (`gh`)・PAT・OAuth tokenを置きません。**

GitHubのブラウザ画面で表示される短時間有効なConfigureコマンドだけを、その場で安全に貼り付けます。

```text
./config.sh --url https://github.com/Daiki-Yoshida/TestGitHubActions --token ********
```

それ以外のDownload / checksum validation / extract / labels / systemd service化はmanagerが自動化します。

## 想定ホスト

- 常時稼働のUbuntu VPS
- Windows上のWSL Ubuntu

Organization runnerを前提にせず、個人アカウント配下に多数あるprivate repositoryへrepository-level runnerを追加する運用を対象にしています。

## Security goal

Runnerホストに長期GitHub credentialを保存しないことを最優先します。

```text
Browser (GitHub authenticated)
  |
  |  one-hour Configure token (manual paste)
  v
runner-manager on VPS / WSL
  |
  +--> public actions/runner release API (no auth)
  +--> official runner package + SHA-256 digest
  +--> config.sh
  +--> systemd

No gh auth / PAT / GitHub OAuth credential on the runner host.
```

登録tokenは入力時にechoせず、managerのstateにも保存しません。upstream `config.sh` の引数として渡す瞬間だけprocess argumentsから観測可能です。

## Important: runner version and GitHub progressive rollout

GitHub Actions Runnerはprogressive releaseです。そのため、public `actions/runner` の最新releaseと、特定repositoryの `Settings -> Actions -> Runners -> New self-hosted runner` が案内するversionが一時的に異なる場合があります。

通常はpublic latestを自動選択します。

```bash
runner-manager add
```

GitHubのDownload欄が別versionを表示している場合だけ、そのversionを明示してください。

```bash
runner-manager add --version 2.336.0
```

version番号だけ指定すれば、download URLとSHA-256 digestはpublicなofficial `actions/runner` release metadataからmanagerが取得します。

## Runner package integrity

managerはpublic GitHub REST APIから `actions/runner` release assetを取得し、asset metadataの `digest` (`sha256:...`) を使ってdownloadしたarchiveを検証します。

つまりGitHub画面の以下は手入力不要です。

```text
curl -o actions-runner-linux-x64-....tar.gz ...
echo "<sha256> ..." | shasum -a 256 -c
tar xzf ...
```

## Install

このrepositoryを**public repositoryとして運用することを推奨**します。そうすればRunnerホストはGitHub認証なしで取得できます。

### Cloneして確認してからinstall（推奨）

```bash
git clone https://github.com/Daiki-Yoshida/self-hosted-runner-manager.git
cd self-hosted-runner-manager
./install.sh
```

### Public bootstrap script

repositoryをpublic化した後は、GitHub credentialなしでbootstrapできます。

セキュリティ上、いきなり`curl | sudo sh`にはせず、いったん保存して内容を確認する運用を推奨します。

```bash
curl -fsSL \
  https://raw.githubusercontent.com/Daiki-Yoshida/self-hosted-runner-manager/main/bootstrap.sh \
  -o /tmp/self-hosted-runner-manager-bootstrap.sh

less /tmp/self-hosted-runner-manager-bootstrap.sh
bash /tmp/self-hosted-runner-manager-bootstrap.sh
```

`bootstrap.sh` 自体はpublic GitHubからsource archiveを取得して通常の`install.sh`を実行するだけで、GitHub認証は行いません。将来tag運用にした場合は `SHRM_REF` で取得refを固定できます。

```bash
SHRM_REF=v0.2.0 bash /tmp/self-hosted-runner-manager-bootstrap.sh
```

インストール先:

```text
/usr/local/bin/runner-manager
/usr/local/lib/self-hosted-runner-manager/
```

必要コマンド:

- `curl`
- `tar`
- `sha256sum`
- `python3` (public GitHub release JSONの安全なparse用)
- `sudo`
- `systemd`

`gh` は不要です。

## 1. Host initialization

ホストごとに一度だけ実行します。

### XServer VPS

```bash
runner-manager init --profile xserver
runner-manager doctor
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
runner-manager doctor
```

Default custom labels:

```text
personal-ci
desktop-wsl
high-memory
```

`init` は専用Unix user `gha-runner`、runner root/cache/state、Ubuntu `needrestart` overrideを準備します。`gha-runner` にsudoやDocker groupは与えません。

## 2. Add a repository runner

GitHubブラウザで対象repositoryを開きます。

```text
Settings
-> Actions
-> Runners
-> New self-hosted runner
-> Linux / x64
```

その後VPS/WSLで:

```bash
runner-manager add
```

managerが次のようにpromptします。

```text
Paste ONLY the Configure line shown by GitHub. Input is hidden so the token is not echoed.
Example: ./config.sh --url https://github.com/OWNER/REPO --token ********
>
```

ここへGitHubのConfigure欄の1行だけpasteします。

```text
./config.sh --url https://github.com/Daiki-Yoshida/TestGitHubActions --token ********
```

managerはURLからrepositoryを認識します。tokenは保存しません。

その後自動で:

1. host architectureを選択
2. official `actions/runner` release metadata取得
3. Linux runner archive取得
4. SHA-256 digest検証
5. versioned cacheへ保存
6. repository専用runtime directoryへ展開
7. `gha-runner` としてofficial `config.sh` 実行
8. host profile labels設定
9. GitHub公式 `svc.sh` でsystemd service化
10. service active確認

を実行します。

### GitHub画面とversionが違う場合

例としてGitHub画面が `2.336.0` を案内しているなら:

```bash
runner-manager add --version 2.336.0
```

Configureコマンドのpaste方法は同じです。

## 3. Workflow selector

VPSのみ:

```yaml
runs-on: [self-hosted, xserver]
```

Desktop WSLのみ:

```yaml
runs-on: [self-hosted, desktop-wsl]
```

どちらでもよい場合:

```yaml
runs-on: [self-hosted, personal-ci]
```

`personal-ci` はpriority/fallbackではありません。複数matching runnerがonline + idleならGitHubがeligible runnerを選択します。

## 4. Status

```bash
runner-manager list
runner-manager status
runner-manager status Daiki-Yoshida/TestGitHubActions
```

v0.2ではGitHub credentialをホストに持たないため、`status` はlocal systemd/stateを確認します。remote GitHub statusはブラウザのActions Runner画面で確認します。

## 5. Remove

```bash
runner-manager remove Daiki-Yoshida/TestGitHubActions
```

managerがGitHubのRunner removal画面を案内します。そこで表示される:

```text
./config.sh remove --token ********
```

をhidden promptへpasteします。remove tokenも保存しません。

## State and runtime

Host configuration:

```text
/etc/self-hosted-runner-manager/config
```

Per-repository non-secret state:

```text
/etc/self-hosted-runner-manager/runners/<owner>--<repo>.conf
```

Runner runtime:

```text
/opt/github-actions-runners/<owner>--<repo>/
```

Versioned package cache:

```text
/var/cache/self-hosted-runner-manager/
```

## Multiple repositories on one host

Repository-level runnersは独立processです。10 repositoryを1台に登録すると、理論上10 jobを同時にacceptできます。

4-core / 6-GB VPSでは危険なため、host-wide concurrency limitは別途設計対象です。v0.2はまだ「全repository合計1 job」を保証しません。

## Security boundary

このmanagerは以下を変更しません。

- SSH
- UFW
- XServer packet filter
- Tailscale
- Docker permission
- repository workflow

Self-hosted runnerで実行可能なrepositoryは、そのホストのrunner権限を信頼できるprivate repositoryに限定してください。

詳細は [`documents/security.md`](documents/security.md) と [`documents/architecture.md`](documents/architecture.md) を参照してください。
