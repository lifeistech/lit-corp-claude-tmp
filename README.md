# lit-corp-claude-tmp

コーポレート部（総務・労務・人事・経理・採用）向けの Claude Code セットアップテンプレート。

- ワンライナーで **Claude Code のインストール → 設定 → 部門別エージェント生成** までを完結
- 削除・上書き・機密ファイルへのアクセスに **承認フロー** を必須化
- プロンプトに混入した **APIキー・パスワードを即ブロック**
- モデル名 / 5時間レート制限 / コンテキストウィンドウを **ステータスラインで可視化**（JST表示）

## 要件

- **Mac**: macOS 12+ / sudo パスワードが分かること（Homebrew 新規導入時のみ必要）
- **Windows**: Windows 10 1809+ / Windows 11（winget が既定で使える）
- Claude.ai Pro / Max サブスクリプション（または API キー）

Node.js・git・Claude Code は **未導入であれば自動でインストール** します。手動準備は不要です。

## インストール（ワンライナー）

### macOS
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lifeistech/lit-corp-claude-tmp/main/install.sh)"
```
途中で Mac のログインパスワードを求められることがあります（Homebrew 新規導入時）。

### Windows (PowerShell)
```powershell
iwr -useb https://raw.githubusercontent.com/lifeistech/lit-corp-claude-tmp/main/install.ps1 | iex
```
UAC プロンプトが出た場合は「はい」を選んでください（winget が初回起動時）。

### 実行される処理

1. **Node.js / git の自動導入**（未導入時のみ）
   - Mac: Homebrew 未導入なら Homebrew → `brew install node git`
   - Windows: `winget install OpenJS.NodeJS.LTS Git.Git`
2. `npm i -g @anthropic-ai/claude-code` で Claude Code を導入
3. **カレントディレクトリ配下**に `lit-corp-claude-tmp/` を作成してテンプレートを clone（例: `~/Desktop` で実行 → `~/Desktop/lit-corp-claude-tmp/` が作られる）
4. 対話セットアップを起動（導入先 / 部門 / モデル / コマンド / .gitignore を選択）
5. セットアップ完了後、**自動で `claude` を起動し onboarding フローへ**

### Onboarding（plan モードで部門テンプレを対話仕上げ）

`claude` 起動直後、`.claude/.onboarding.json` のマーカーを読んだ Claude が以下を順次実行します。

- 選択された部門 (accounting / labor / ...) を1つずつ順番に処理
- 各部門について plan モードで以下を質問:
  - 扱うファイル・フォルダ構成
  - よくある定型業務 3〜5 件
  - 禁止事項・社内ルール
  - 利用している社内システム
  - 出力フォーマットの希望
- 回答をもとに `.claude/agents/<dept>.md` の system prompt を書き換え（`ExitPlanMode` で承認）
- 全部門完了後、`.onboarding.json` を `completed` に更新

後から Claude Code を起動し直した場合も、onboarding 未完了なら自動的にこのフローから再開します。

## 対話セットアップで聞かれること

1. **導入先ディレクトリ**（default: カレント）
2. **部門選択（複数可）**
   - 経理 (accounting)
   - 労務 (labor)
   - 総務 (general-affairs)
   - 人事 (hr)
   - 採用 (recruit)
3. **既定モデル** … opus / sonnet
4. **部門別スラッシュコマンドを導入するか**（例: `/月次精算`, `/勤怠確認`）
5. **.gitignore の作成/追記**

## 生成されるファイル構成

```
<導入先>/
├── CLAUDE.md                       # オーケストレーター指示（選択部門への委任ルール）
├── .gitignore                      # .env / 鍵 / credentials など機密を除外
└── .claude/
    ├── settings.json               # permissions (deny/ask) + hooks + statusLine
    ├── statusline.js               # 2行ステータス（モデル / 5h制限 / コンテキスト）
    ├── hooks/secret-guard.js       # プロンプト入力時に機密パターン検知
    ├── agents/<dept>.md            # 部門別サブエージェント
    └── commands/<dept>/*.md        # 部門別スラッシュコマンド
```

## セキュリティ機能の概要

| 対策 | 実装 |
| --- | --- |
| **auto mode / bypassPermissions mode の利用禁止** | `permissions.disableAutoMode: "disable"` + `permissions.disableBypassPermissionsMode: "disable"` |
| 起動モードの固定 | `permissions.defaultMode: "default"` |
| `.env` / `*.pem` / `*.key` / `credentials*` の Read/Edit | `settings.json` の `permissions.deny` |
| 削除・上書き系 (`rm`, `mv`, `Edit`, `Write`, `git push`, `git reset --hard` 等) | `permissions.ask` で承認必須化 |
| プロンプトへの APIキー混入（Anthropic / OpenAI / AWS / GitHub / Google / Slack / PEM 等） | `UserPromptSubmit` hook で exit 2 ブロック |
| 危険な `curl \| bash` などのパイプ実行 | `permissions.deny` |
| 機密のコミット流出 | `.gitignore` テンプレで除外 |

### 禁止モードについて

非エンジニア中心の運用を想定し、以下の承認スキップ系モードは **Claude Code 側で切替不可** にしています:

- `auto` mode — 自律実行
- `bypassPermissions` mode — 全権限回避

Shift+Tab でのモード切替を試みてもシステムが拒否します。`plan` mode（Onboarding で使用）と `acceptEdits` mode は許可。

## ステータスライン表示

```
[Opus] 5h: ▓▓▓░░░░░░░ 30% | Reset: 18:00 JST
Context: ██░░░░░░░░ 24% (48k/200k)
```

- モデル名 / 5時間レート制限バー / JST リセット時刻 / コンテキストウィンドウバー を表示
- Claude.ai サブスクでない場合（rate_limits 情報なし）は 1 行目がモデル名のみにフォールバック
- 使用率 70% 以上で黄色、90% 以上で赤色に変化

## アップデート

```bash
# clone したディレクトリに移動
cd path/to/lit-corp-claude-tmp

git pull
node setup.js     # 再度対話セットアップ
```

## トラブルシュート

| 症状 | 対処 |
| --- | --- |
| `claude: command not found` | `npm i -g @anthropic-ai/claude-code` を再実行、PATH に npm global bin を通す |
| statusline が表示されない | `node .claude/statusline.js < /dev/null` で単体起動し、エラーメッセージを確認 |
| hook でブロックされた誤検知 | 表現を変えて再送信、繰り返し発生するなら `templates/hooks/secret-guard.js` の PATTERNS を調整 |
| Windows で git clone に失敗 | `git config --global core.longpaths true` を設定 |

## 運用メンテナンス

- 部門別テンプレート（`templates/agents/*.md`, `templates/commands/<dept>/*.md`）は業務ルール変更に合わせて随時更新する
- 変更後は `main` に merge すれば、各利用者は clone 済みディレクトリで `git pull && node setup.js` で取り込める
- 従業員向け案内には README 冒頭のワンライナーを貼ればよい（`lifeistech/lit-corp-claude-tmp` が参照される）
