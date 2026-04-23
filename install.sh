#!/usr/bin/env bash
# lit-corp-claude-tmp installer (macOS / Linux)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<org>/lit-corp-claude-tmp/main/install.sh | bash
#
# このスクリプトは未導入の場合に以下を自動インストールします:
#   - Homebrew (sudo パスワード入力を求められます。Mac のログインパスワードを入力してください)
#   - Node.js LTS (brew 経由)
#   - git (brew 経由)
set -euo pipefail

REPO_URL="${LIT_CORP_CLAUDE_TMP_REPO:-https://github.com/lifeistech/lit-corp-claude-tmp.git}"
BRANCH="${LIT_CORP_CLAUDE_TMP_BRANCH:-main}"
TARGET_DIR="${LIT_CORP_CLAUDE_TMP_DIR:-$PWD/lit-corp-claude-tmp}"

cecho() { printf "\033[1;36m[lit-corp-claude-tmp]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
err()   { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; }

cecho "コーポレート部向け Claude Code セットアップを開始します"

# ---------- OS check ----------
UNAME_S="$(uname -s)"
case "$UNAME_S" in
  Darwin)  OS_KIND=mac ;;
  Linux)   OS_KIND=linux ;;
  *)       err "未対応の OS: $UNAME_S"; exit 1 ;;
esac

# ---------- Homebrew bootstrap (Mac only, if needed) ----------
ensure_brew_path() {
  if command -v brew >/dev/null 2>&1; then return 0; fi
  # Apple Silicon: /opt/homebrew, Intel: /usr/local
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_brew() {
  if [ "$OS_KIND" != "mac" ]; then
    err "Linux 環境では自動 brew 導入は行いません。apt/yum 等でお手元の node と git を先に入れてから再実行してください"
    exit 1
  fi
  cecho "Homebrew を自動インストールします"
  warn  "このあと sudo パスワード入力を求められます（Mac のログインパスワードを入力してください）"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ensure_brew_path
  if ! command -v brew >/dev/null 2>&1; then
    err "Homebrew の導入に失敗しました。https://brew.sh/ を参照して手動導入後、再実行してください"
    exit 1
  fi
  cecho "Homebrew 導入完了: $(brew --version | head -1)"
}

ensure_brew_path

# ---------- Node.js ----------
ensure_node() {
  if command -v node >/dev/null 2>&1; then
    local v
    v="$(node -p 'parseInt(process.versions.node.split(".")[0],10)')"
    if [ "$v" -ge 18 ]; then
      cecho "Node.js 確認: $(node -v)"
      return 0
    fi
    warn "Node.js のバージョンが古いため更新します (現在: $(node -v))"
  else
    cecho "Node.js が見つからないため自動インストールします"
  fi
  command -v brew >/dev/null 2>&1 || install_brew
  brew install node
  cecho "Node.js 導入完了: $(node -v)"
}

# ---------- git ----------
ensure_git() {
  if command -v git >/dev/null 2>&1; then
    cecho "git 確認: $(git --version)"
    return 0
  fi
  cecho "git が見つからないため自動インストールします"
  command -v brew >/dev/null 2>&1 || install_brew
  brew install git
  cecho "git 導入完了: $(git --version)"
}

ensure_node
ensure_git

# ---------- Claude Code ----------
if ! command -v claude >/dev/null 2>&1; then
  cecho "Claude Code をインストールします (npm i -g @anthropic-ai/claude-code)"
  if ! npm i -g @anthropic-ai/claude-code; then
    err "Claude Code のインストールに失敗しました。npm の権限設定を確認してください"
    err "(参考: https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally)"
    exit 1
  fi
else
  cecho "Claude Code は既にインストール済み ($(claude --version 2>/dev/null || echo 'version unknown'))"
fi

# ---------- Repo fetch ----------
if [ -d "$TARGET_DIR/.git" ]; then
  cecho "既存のテンプレートを更新します ($TARGET_DIR)"
  git -C "$TARGET_DIR" pull --ff-only
else
  cecho "テンプレートを $TARGET_DIR に取得します"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
fi

# ---------- Launch setup ----------
cecho "対話セットアップを起動します"
cd "$TARGET_DIR"
exec node "$TARGET_DIR/setup.js" "$@"
