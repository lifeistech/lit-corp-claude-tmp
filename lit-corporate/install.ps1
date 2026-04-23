# lit-corporate installer (Windows / PowerShell)
# Usage:
#   iwr -useb https://raw.githubusercontent.com/<org>/lit-corporate/main/install.ps1 | iex
#
# このスクリプトは未導入の場合に winget 経由で Node.js LTS / Git を自動インストールします。
# UAC プロンプトが出た場合は許可してください。
$ErrorActionPreference = 'Stop'

$RepoUrl   = if ($env:LIT_CORPORATE_REPO)   { $env:LIT_CORPORATE_REPO }   else { 'https://github.com/lifeistech/lit-corporate.git' }
$Branch    = if ($env:LIT_CORPORATE_BRANCH) { $env:LIT_CORPORATE_BRANCH } else { 'main' }
$TargetDir = if ($env:LIT_CORPORATE_DIR)    { $env:LIT_CORPORATE_DIR }    else { Join-Path $HOME 'lit-corporate' }

function Write-Info($msg) { Write-Host "[lit-corporate] $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Write-Err ($msg) { Write-Host "[error] $msg" -ForegroundColor Red }

Write-Info "コーポレート部向け Claude Code セットアップを開始します"

# ---------- PATH refresh helper ----------
function Update-SessionPath {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

# ---------- winget check ----------
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
    # --silent で対話最小化、--accept-*-agreements でライセンス同意を事前承諾
    $proc = Start-Process -FilePath 'winget' `
        -ArgumentList @('install', '--id', $id, '-e',
                        '--accept-source-agreements', '--accept-package-agreements',
                        '--silent') `
        -Wait -PassThru -NoNewWindow
    # winget の exit code: 0=成功, -1978335189=既にインストール済み
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne -1978335189) {
        Write-Err "$displayName のインストールに失敗しました (exit $($proc.ExitCode))"
        exit 1
    }
    Update-SessionPath
}

# ---------- Node.js ----------
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

# ---------- git ----------
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

# ---------- Claude Code ----------
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

# ---------- Launch setup ----------
Write-Info "対話セットアップを起動します"
Set-Location $TargetDir
& node (Join-Path $TargetDir 'setup.js') $args
exit $LASTEXITCODE
