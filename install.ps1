# lit-corp-claude-tmp installer (Windows / PowerShell)
# Usage:
#   iwr -useb https://raw.githubusercontent.com/lifeistech/lit-corp-claude-tmp/main/install.ps1 | iex
#
# 実行内容:
#   1. Node.js LTS / Git / Claude Code を必要に応じて winget/npm で自動インストール
#   2. テンプレートを clone
#   3. .claude/ 設定一式 と CLAUDE.md / .gitignore を展開（部門選定はしない）
#   4. claude を plan モードで起動し Onboarding フローへ
$ErrorActionPreference = 'Stop'

$RepoUrl   = if ($env:LIT_CORP_CLAUDE_TMP_REPO)   { $env:LIT_CORP_CLAUDE_TMP_REPO }   else { 'https://github.com/lifeistech/lit-corp-claude-tmp.git' }
$Branch    = if ($env:LIT_CORP_CLAUDE_TMP_BRANCH) { $env:LIT_CORP_CLAUDE_TMP_BRANCH } else { 'main' }
$TargetDir = if ($env:LIT_CORP_CLAUDE_TMP_DIR)    { $env:LIT_CORP_CLAUDE_TMP_DIR }    else { Join-Path $PWD.Path 'lit-corp-claude-tmp' }

function Write-Info($msg) { Write-Host "[lit-corp-claude-tmp] $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Write-Err ($msg) { Write-Host "[error] $msg" -ForegroundColor Red }

Write-Info "コーポレート部向け Claude Code セットアップを開始します"

function Update-SessionPath {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Ensure-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }
    Write-Err "winget が見つかりません。Windows 10 1809+ / Windows 11 が必要です"
    Write-Err "Microsoft Store から『アプリ インストーラー』を導入してから再実行してください:"
    Write-Err "  https://apps.microsoft.com/detail/9nblggh4nns1"
    exit 1
}

function Install-WithWinget($id, $displayName) {
    Ensure-Winget
    Write-Info "$displayName を winget 経由でインストールします ($id)"
    Write-Warn "UAC プロンプトが出た場合は『はい』を選んでください"
    $proc = Start-Process -FilePath 'winget' `
        -ArgumentList @('install', '--id', $id, '-e',
                        '--accept-source-agreements', '--accept-package-agreements',
                        '--silent') `
        -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne -1978335189) {
        Write-Err "$displayName のインストールに失敗しました (exit $($proc.ExitCode))"
        exit 1
    }
    Update-SessionPath
}

function Ensure-Node {
    if (Get-Command node -ErrorAction SilentlyContinue) {
        $v = [int](& node -p "parseInt(process.versions.node.split('.')[0],10)")
        if ($v -ge 18) {
            Write-Info ("Node.js 確認: " + (node -v))
            return
        }
        Write-Warn ("Node.js のバージョンが古いため更新します (現在: " + (node -v) + ")")
    } else {
        Write-Info "Node.js が見つからないため自動インストールします"
    }
    Install-WithWinget 'OpenJS.NodeJS.LTS' 'Node.js LTS'
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Err "Node.js の導入後も node コマンドが見つかりません。PowerShell を開き直して再実行してください"
        exit 1
    }
    Write-Info ("Node.js 導入完了: " + (node -v))
}

function Ensure-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Info ("git 確認: " + (git --version))
        return
    }
    Write-Info "git が見つからないため自動インストールします"
    Install-WithWinget 'Git.Git' 'Git'
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Err "Git の導入後も git コマンドが見つかりません。PowerShell を開き直して再実行してください"
        exit 1
    }
    Write-Info ("git 導入完了: " + (git --version))
}

Ensure-Node
Ensure-Git

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Info "Claude Code をインストールします (npm i -g @anthropic-ai/claude-code)"
    npm i -g '@anthropic-ai/claude-code'
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Claude Code のインストールに失敗しました。管理者 PowerShell で再実行するか、npm prefix の設定を確認してください"
        exit 1
    }
    Update-SessionPath
} else {
    Write-Info "Claude Code は既にインストール済み"
}

# ---------- Repo fetch ----------
if (Test-Path (Join-Path $TargetDir '.git')) {
    Write-Info "既存のテンプレートを更新します ($TargetDir)"
    git -C $TargetDir pull --ff-only
} else {
    Write-Info "テンプレートを $TargetDir に取得します"
    git clone --depth 1 --branch $Branch $RepoUrl $TargetDir
}

# ---------- Bootstrap files ----------
Write-Info "設定ファイルを展開します（部門は Onboarding でヒアリング）"
$claudeDir = Join-Path $TargetDir '.claude'
$hooksDir  = Join-Path $claudeDir 'hooks'
New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null

Copy-Item (Join-Path $TargetDir 'templates\settings.json')        (Join-Path $claudeDir 'settings.json')        -Force
Copy-Item (Join-Path $TargetDir 'templates\statusline.js')        (Join-Path $claudeDir 'statusline.js')        -Force
Copy-Item (Join-Path $TargetDir 'templates\hooks\secret-guard.js') (Join-Path $hooksDir  'secret-guard.js')     -Force

$claudeMd = Join-Path $TargetDir 'CLAUDE.md'
if (Test-Path $claudeMd) { Copy-Item $claudeMd "$claudeMd.bak" -Force }
Copy-Item (Join-Path $TargetDir 'templates\CLAUDE.md.tmpl') $claudeMd -Force

# .gitignore は強制作成（既存があれば .bak へ）
$gitignore = Join-Path $TargetDir '.gitignore'
if (Test-Path $gitignore) { Copy-Item $gitignore "$gitignore.bak" -Force }
Copy-Item (Join-Path $TargetDir 'templates\gitignore.template') $gitignore -Force

# Onboarding marker
$marker = [pscustomobject]@{
    createdAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    status    = 'pending'
    model     = 'sonnet'
}
$marker | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $claudeDir '.onboarding.json')

# ---------- Launch claude in plan mode ----------
Set-Location $TargetDir

$OnboardingPrompt = @'
【初回 Onboarding — Plan モード】
CLAUDE.md の「初回 Onboarding」セクションの手順に従って、部門と機能サブエージェント（二層構成）を確定させてください。

前提（解釈 A: 1 インストール = 1 部門、二層構成）:
- ルート CLAUDE.md = 部門 AI オーケストレーター
- 機能サブエージェントごとに 2 ファイル:
  1) `.claude/agents/<英語id>.md` … ルーティング定義（frontmatter の description で自動委任）
  2) `<日本語ディレクトリ>/CLAUDE.md` … 詳細運用ルール（そのディレクトリで作業すると自動で context に読み込まれる）

**重要: ユーザーへの質問はすべて `AskUserQuestion` ツール**を使う（自由記述必要な項目は「その他（自由記述）」を含め、複数項目は 1 回の呼び出しで `questions` 配列にまとめる）。

概要:
1. 部門を 1 つだけ選ぶ（単一選択）。候補は 経理/労務/総務/人事/採用/情シス/その他。英語 id と日本語表示名を確定
2. 部門コンテキスト（ファイル構成・禁止操作・利用ツール・出力フォーマット）を 1 セットにまとめて聞き取る
3. 機能サブエージェント（担当領域）3〜8 件を洗い出す（例: 情シスなら ID管理/端末管理/インシデント管理/ヘルプデスク 等）
4. 各機能について: 英語 id / 日本語表示名（ディレクトリ名にもなる）/ 業務サマリ / 入出力 / 手順のツボ / 禁止事項を聞き取る
5. `ExitPlanMode` で承認を得る
6. 承認後に書き込む:
   - ルート `CLAUDE.md` を「<部門名> AI オーケストレーター」として全面書き換え（委任ルール一覧・`<!-- BEGIN:ONBOARDING -->` 〜 `<!-- END:ONBOARDING -->` を削除）
   - 機能サブエージェントを 2 ファイルずつ作成:
     a) `.claude/agents/<英語id>.md` … frontmatter の model は必ず `sonnet`、本文は短く「まず `<日本語ディレクトリ>/CLAUDE.md` を Read してから作業」と明記
     b) `<日本語ディレクトリ>/CLAUDE.md` … 詳細運用ルール
   - `.claude/.onboarding.json` を `status: "completed"`, `completedAt`, `department`, `agents` で更新
7. 「Onboarding 完了」を宣言し、Next Actions を提示（各機能サブエージェントへの依頼例・モード運用・機密ブロック挙動・再編集方法・Onboarding 再実行方法）

スラッシュコマンドは作成しないでください。それでは step 1 の質問から始めてください。
'@

Write-Info "claude を plan モードで起動します"
& claude --permission-mode plan $OnboardingPrompt
exit $LASTEXITCODE
