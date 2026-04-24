#!/usr/bin/env bash
# lit-corp-claude-tmp installer (macOS / Linux)
# Usage:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/lifeistech/lit-corp-claude-tmp/main/install.sh)"
#
# 実行内容:
#   1. Homebrew / Node.js / git / Claude Code を必要に応じて自動インストール
#   2. テンプレートを clone
#   3. .claude/ 設定一式 と CLAUDE.md / .gitignore を展開（部門選定は行わない）
#   4. claude を plan モードで自動起動し Onboarding フローへ
set -euo pipefail

if [ ! -t 0 ] && [ -r /dev/tty ]; then
  exec 0</dev/tty
fi

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

ensure_brew_path() {
  if command -v brew >/dev/null 2>&1; then return 0; fi
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_brew() {
  if [ "$OS_KIND" != "mac" ]; then
    err "Linux 環境では自動 brew 導入は行いません。apt/yum 等で node と git を先に入れてから再実行してください"
    exit 1
  fi
  cecho "Homebrew を自動インストールします"
  warn  "sudo パスワード入力を求められます（Mac のログインパスワード）"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ensure_brew_path
  if ! command -v brew >/dev/null 2>&1; then
    err "Homebrew の導入に失敗しました。https://brew.sh/ を参照して手動導入後、再実行してください"
    exit 1
  fi
  cecho "Homebrew 導入完了: $(brew --version | head -1)"
}

ensure_brew_path

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

# ---------- Bootstrap files ----------
cecho "設定ファイルを展開します（部門は Onboarding でヒアリング）"
mkdir -p "$TARGET_DIR/.claude/hooks"
cp "$TARGET_DIR/templates/settings.json"        "$TARGET_DIR/.claude/settings.json"
cp "$TARGET_DIR/templates/statusline.js"        "$TARGET_DIR/.claude/statusline.js"
cp "$TARGET_DIR/templates/hooks/secret-guard.js" "$TARGET_DIR/.claude/hooks/secret-guard.js"

# CLAUDE.md は既存があっても上書き（.bak を残す）
if [ -f "$TARGET_DIR/CLAUDE.md" ]; then
  cp "$TARGET_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md.bak"
fi
cp "$TARGET_DIR/templates/CLAUDE.md.tmpl" "$TARGET_DIR/CLAUDE.md"

# .gitignore は強制作成（既存がある場合も上書き）
if [ -f "$TARGET_DIR/.gitignore" ]; then
  cp "$TARGET_DIR/.gitignore" "$TARGET_DIR/.gitignore.bak"
fi
cp "$TARGET_DIR/templates/gitignore.template" "$TARGET_DIR/.gitignore"

# Onboarding marker
cat > "$TARGET_DIR/.claude/.onboarding.json" <<EOF
{
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "pending",
  "model": "sonnet"
}
EOF

# ---------- Launch claude in plan mode ----------
cd "$TARGET_DIR"

ONBOARDING_PROMPT=$(cat <<'PROMPT'
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
6. 「Onboarding 完了」を宣言

スラッシュコマンドは作成しないでください。それでは step 1 の質問から始めてください。
PROMPT
)

cecho "claude を plan モードで起動します"
exec claude --permission-mode plan "$ONBOARDING_PROMPT"
