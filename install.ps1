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
コーポレート部向け Claude Code 設定の対話仕上げを行います。CLAUDE.md の「初回 Onboarding」セクションの手順に従って進めてください。

**重要: ユーザーへの質問はすべて `AskUserQuestion` ツールを使ってください**（平文ではなく構造化 UI で提示）。自由記述が要るものは選択肢に「その他（自由記述）」を含めること。複数項目は 1 回の呼び出しで `questions` 配列にまとめる。

概要:
1. 導入する部門をヒアリング（既定: 経理/労務/総務/人事/採用。「その他」として任意追加可。id は英小文字ハイフン）— AskUserQuestion の複数選択で提示
2. 選ばれた各部門について、扱うファイル構成・定型業務・禁止操作・利用ツール・出力フォーマットを AskUserQuestion で 1 セットにまとめて質問
3. 既定部門は `templates/agents/<id>.md` を Read して参考にする。「その他」は新規作成
4. `ExitPlanMode` で最終プランを提示し、私の承認を得る
5. 承認後、以下を書き込む:
   - `.claude/agents/<id>.md` を作成（frontmatter の model は必ず `sonnet`）
   - `CLAUDE.md` の `<!-- BEGIN:DEPARTMENTS -->` / `<!-- END:DEPARTMENTS -->` 間を部門リストで置換
   - `.claude/.onboarding.json` を `status: "completed"`, `completedAt`, `departments` で更新
6. **`CLAUDE.md` の `<!-- BEGIN:ONBOARDING -->` から `<!-- END:ONBOARDING -->` までをセクションごと削除**
7. 「Onboarding 完了」を宣言し、**Next Actions を提示**:
   - 各部門への依頼例 2〜3 件
   - `/plan`・`acceptEdits` モードの使い分け、`/help` の案内
   - 機密ブロック・削除系承認プロンプトの挙動
   - 部門テンプレ再編集（`.claude/agents/<id>.md`）、Onboarding 再実行方法

スラッシュコマンドは作成しないでください。それでは step 1 の質問から始めてください。
'@

Write-Info "claude を plan モードで起動します"
& claude --permission-mode plan $OnboardingPrompt
exit $LASTEXITCODE
