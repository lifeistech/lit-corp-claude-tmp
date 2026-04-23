#!/usr/bin/env node
// lit-corporate interactive setup
// テンプレート（templates/）から選択した部門の .claude/ 設定一式を target に展開する。
//
// 使い方:
//   対話モード:   node setup.js
//   非対話モード: node setup.js --target /tmp/lit-test --depts accounting,hr --model sonnet --commands --non-interactive
//
// 対話フロー:
//   1. 導入先ディレクトリ確認（default: カレント）
//   2. 部門選択（複数可）: accounting / labor / general-affairs / hr / recruit
//   3. 既定モデル: opus / sonnet
//   4. 部門別スラッシュコマンドも導入するか（Y/n）
//   5. .gitignore 作成/追記するか（Y/n）

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const readline = require('node:readline/promises');
const { spawn, spawnSync } = require('node:child_process');

const TEMPLATE_DIR = path.join(__dirname, 'templates');

const DEPARTMENTS = [
  { id: 'accounting',       label: '経理 (accounting)',      summary: '仕訳・月次精算・決算・監査対応' },
  { id: 'labor',            label: '労務 (labor)',           summary: '勤怠・36協定・給与計算・労働法令' },
  { id: 'general-affairs',  label: '総務 (general-affairs)', summary: '備品・契約書・社内イベント・規程' },
  { id: 'hr',               label: '人事 (hr)',              summary: '評価・研修・1on1・タレントマネジメント' },
  { id: 'recruit',          label: '採用 (recruit)',         summary: '求人票・候補者整理・面接・入社手続' },
];

const MODELS = ['opus', 'sonnet'];

// ---------- CLI args ----------
function parseArgs(argv) {
  const out = { nonInteractive: false, commands: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === '--target') out.target = next();
    else if (a === '--depts') out.depts = next().split(',').map((s) => s.trim()).filter(Boolean);
    else if (a === '--model') out.model = next();
    else if (a === '--commands') out.commands = true;
    else if (a === '--no-commands') out.commands = false;
    else if (a === '--non-interactive') out.nonInteractive = true;
    else if (a === '--gitignore') out.gitignore = true;
    else if (a === '--no-gitignore') out.gitignore = false;
    else if (a === '--launch-claude') out.launchClaude = true;
    else if (a === '--no-launch-claude') out.launchClaude = false;
    else if (a === '-h' || a === '--help') out.help = true;
  }
  return out;
}

function printHelp() {
  console.log(`lit-corporate setup

使い方:
  node setup.js                                対話モード
  node setup.js --non-interactive --depts accounting,hr --model sonnet --commands

オプション:
  --target <dir>        導入先ディレクトリ (default: カレント)
  --depts <list>        カンマ区切りで部門を指定: ${DEPARTMENTS.map((d) => d.id).join(', ')}
  --model <name>        既定モデル: ${MODELS.join(' | ')}
  --commands            部門別スラッシュコマンドを導入
  --no-commands         スラッシュコマンドを導入しない
  --launch-claude       完了後に claude を自動起動（対話モード既定: on、非対話既定: off）
  --no-launch-claude    完了後に claude を起動しない
  --gitignore           .gitignore を作成/追記
  --no-gitignore        .gitignore を作成しない
  --non-interactive     対話プロンプトをスキップ（CI 用）
  -h, --help            このヘルプ
`);
}

// ---------- prompt helpers ----------
async function ask(rl, question, defaultValue = '') {
  const suffix = defaultValue ? ` (${defaultValue})` : '';
  const ans = (await rl.question(`${question}${suffix}: `)).trim();
  return ans || defaultValue;
}

async function askYesNo(rl, question, def = true) {
  const hint = def ? 'Y/n' : 'y/N';
  const ans = (await rl.question(`${question} [${hint}]: `)).trim().toLowerCase();
  if (!ans) return def;
  return ans.startsWith('y');
}

async function askMultiSelect(rl, question, items) {
  console.log(`\n${question}`);
  items.forEach((it, i) => {
    console.log(`  ${i + 1}) ${it.label} — ${it.summary}`);
  });
  const raw = (await rl.question(
    '番号をカンマ/スペース区切りで入力（例: 1,3,5  all で全選択）: '
  )).trim().toLowerCase();
  if (!raw || raw === 'all') return items.map((it) => it.id);
  const picks = new Set();
  raw.split(/[,\s]+/).forEach((tok) => {
    const n = parseInt(tok, 10);
    if (!Number.isNaN(n) && n >= 1 && n <= items.length) picks.add(items[n - 1].id);
    else if (items.find((it) => it.id === tok)) picks.add(tok);
  });
  return [...picks];
}

async function askChoice(rl, question, choices, def) {
  console.log(`\n${question}`);
  choices.forEach((c, i) => console.log(`  ${i + 1}) ${c}${c === def ? ' (default)' : ''}`));
  const raw = (await rl.question('選択: ')).trim();
  if (!raw) return def;
  const n = parseInt(raw, 10);
  if (!Number.isNaN(n) && n >= 1 && n <= choices.length) return choices[n - 1];
  if (choices.includes(raw)) return raw;
  return def;
}

// ---------- fs helpers ----------
function expandHome(p) {
  if (!p) return p;
  if (p === '~') return os.homedir();
  if (p.startsWith('~/') || p.startsWith('~\\')) return path.join(os.homedir(), p.slice(2));
  return p;
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function copyFile(src, dst) {
  ensureDir(path.dirname(dst));
  fs.copyFileSync(src, dst);
}

function readTemplate(rel) {
  return fs.readFileSync(path.join(TEMPLATE_DIR, rel), 'utf8');
}

function writeFile(dst, content) {
  ensureDir(path.dirname(dst));
  fs.writeFileSync(dst, content);
}

function copyDirRecursive(srcDir, dstDir) {
  if (!fs.existsSync(srcDir)) return;
  ensureDir(dstDir);
  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const s = path.join(srcDir, entry.name);
    const d = path.join(dstDir, entry.name);
    if (entry.isDirectory()) copyDirRecursive(s, d);
    else copyFile(s, d);
  }
}

// ---------- generators ----------
function renderClaudeMd(depts) {
  const tmpl = readTemplate('CLAUDE.md.tmpl');
  const selected = DEPARTMENTS.filter((d) => depts.includes(d.id));
  const list = selected
    .map((d) => `- ${d.summary.replace(/・/g, '、')} に関する依頼は **@${d.id}** に委任してください`)
    .join('\n');
  return tmpl.replace('{{departments}}', list || '- （部門が選択されていません。setup を再実行してください）');
}

function renderAgentMd(deptId, model) {
  const raw = readTemplate(path.join('agents', `${deptId}.md`));
  return raw.replace(/\{\{MODEL\}\}/g, model);
}

function writeSettings(targetDir) {
  const src = path.join(TEMPLATE_DIR, 'settings.json');
  const dst = path.join(targetDir, '.claude', 'settings.json');
  copyFile(src, dst);
}

function writeStatuslineAndHook(targetDir) {
  copyFile(path.join(TEMPLATE_DIR, 'statusline.js'),
           path.join(targetDir, '.claude', 'statusline.js'));
  copyFile(path.join(TEMPLATE_DIR, 'hooks', 'secret-guard.js'),
           path.join(targetDir, '.claude', 'hooks', 'secret-guard.js'));
}

function writeAgents(targetDir, depts, model) {
  for (const d of depts) {
    writeFile(path.join(targetDir, '.claude', 'agents', `${d}.md`),
              renderAgentMd(d, model));
  }
}

function writeCommands(targetDir, depts) {
  for (const d of depts) {
    const src = path.join(TEMPLATE_DIR, 'commands', d);
    const dst = path.join(targetDir, '.claude', 'commands', d);
    copyDirRecursive(src, dst);
  }
}

function writeGitignore(targetDir) {
  const tmpl = readTemplate('gitignore.template');
  const dst = path.join(targetDir, '.gitignore');
  if (fs.existsSync(dst)) {
    const existing = fs.readFileSync(dst, 'utf8');
    if (existing.includes('lit-corporate — 機密ファイル除外リスト')) {
      console.log('  · .gitignore: 既にテンプレ済み、スキップ');
      return;
    }
    fs.writeFileSync(dst, existing + '\n\n# --- lit-corporate 追記 ---\n' + tmpl);
    console.log('  · .gitignore: 既存ファイルに追記');
  } else {
    writeFile(dst, tmpl);
    console.log('  · .gitignore: 新規作成');
  }
}

function writeClaudeMd(targetDir, depts) {
  const dst = path.join(targetDir, 'CLAUDE.md');
  if (fs.existsSync(dst)) {
    console.log('  · CLAUDE.md: 既存あり、.bak に退避して上書き');
    fs.copyFileSync(dst, dst + '.bak');
  }
  writeFile(dst, renderClaudeMd(depts));
}

// ---------- main ----------
async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) { printHelp(); return; }

  console.log('\n== lit-corporate セットアップ ==\n');

  let targetDir, depts, model, includeCommands, includeGitignore;

  if (args.nonInteractive) {
    targetDir = expandHome(args.target || process.cwd());
    depts = args.depts || [];
    model = args.model || 'sonnet';
    includeCommands = args.commands !== false;
    includeGitignore = args.gitignore !== false;
  } else {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    try {
      targetDir = expandHome(
        await ask(rl, '導入先ディレクトリ', args.target || process.cwd())
      );
      depts = args.depts && args.depts.length
        ? args.depts
        : await askMultiSelect(rl, '導入する部門を選んでください', DEPARTMENTS);
      model = args.model || await askChoice(rl, '既定モデルを選択', MODELS, 'sonnet');
      includeCommands = args.commands != null
        ? args.commands
        : await askYesNo(rl, '部門別スラッシュコマンドも導入しますか？', true);
      includeGitignore = args.gitignore != null
        ? args.gitignore
        : await askYesNo(rl, '.gitignore を作成/追記しますか？', true);
    } finally {
      rl.close();
    }
  }

  // validate
  const validIds = new Set(DEPARTMENTS.map((d) => d.id));
  depts = depts.filter((d) => validIds.has(d));
  if (depts.length === 0) {
    console.error('部門が1つも選択されていません。setup を中止します。');
    process.exit(1);
  }
  if (!MODELS.includes(model)) {
    console.error(`不明なモデル: ${model} (opus / sonnet のいずれかを指定してください)`);
    process.exit(1);
  }

  console.log('\n生成内容:');
  console.log(`  · 導入先     : ${targetDir}`);
  console.log(`  · 部門       : ${depts.join(', ')}`);
  console.log(`  · 既定モデル : ${model}`);
  console.log(`  · コマンド   : ${includeCommands ? 'あり' : 'なし'}`);
  console.log(`  · gitignore  : ${includeGitignore ? 'あり' : 'なし'}`);
  console.log();

  ensureDir(targetDir);
  writeSettings(targetDir);
  writeStatuslineAndHook(targetDir);
  writeAgents(targetDir, depts, model);
  if (includeCommands) writeCommands(targetDir, depts);
  writeClaudeMd(targetDir, depts);
  if (includeGitignore) writeGitignore(targetDir);
  writeOnboardingMarker(targetDir, depts, model);

  console.log('\n✅ セットアップ完了');

  // 自動起動: 対話モード既定 on、非対話モード既定 off、--launch-claude/--no-launch-claude で明示可
  const shouldLaunch = (args.launchClaude != null)
    ? args.launchClaude
    : !args.nonInteractive;

  if (shouldLaunch) {
    maybeLaunchClaude(targetDir, depts);
  } else {
    console.log(`\n次のコマンドで起動してください:\n  cd "${targetDir}" && claude\n`);
  }
}

// ---------- claude auto-launch ----------
function claudeAvailable() {
  const cmd = process.platform === 'win32' ? 'where' : 'which';
  const probe = spawnSync(cmd, ['claude'], { stdio: 'ignore' });
  return probe.status === 0;
}

function buildOnboardingPrompt(depts) {
  const list = depts.map((d) => `\`.claude/agents/${d}.md\``).join(' / ');
  return [
    '【初回 Onboarding】',
    'これからコーポレート部向けのサブエージェントをあなたと一緒にブラッシュアップします。',
    `対象: ${list}`,
    '',
    '手順:',
    '1. 各部門の .claude/agents/<dept>.md を1つずつ開いて確認する',
    '2. /plan モードに切り替える（もしくは ExitPlanMode が必要なら対応）',
    '3. 以下を私（利用者）に質問して回答を集める:',
    '   - その部門で扱う代表的なファイル・フォルダ構成',
    '   - よくある定型業務 3〜5 件',
    '   - 絶対にやってはいけない/社内ルールで禁止されている操作',
    '   - 利用している社内システム・ツール（無ければ「なし」）',
    '4. 回答をもとに該当部門の .md の system prompt 本文（フロントマターの下）を書き換える',
    '   - フロントマター (name / description / tools / model) は変更しない',
    '   - 既存の記述を残すか置き換えるかは毎回私に確認する',
    '5. ExitPlanMode で私の承認を得てから保存する',
    '6. 次の部門へ進む。全部門終わったら「Onboarding 完了」と宣言して通常モードに戻る',
    '',
    'まずは最初の部門から、step 3 の質問を私に投げてください。',
  ].join('\n');
}

function writeOnboardingMarker(targetDir, depts, model) {
  const p = path.join(targetDir, '.claude', '.onboarding.json');
  writeFile(p, JSON.stringify({
    createdAt: new Date().toISOString(),
    pendingDepts: depts,
    model,
    status: 'pending',
  }, null, 2));
}

function maybeLaunchClaude(targetDir, depts) {
  if (!claudeAvailable()) {
    console.log('\n⚠️  `claude` コマンドが見つからないため自動起動をスキップします。');
    console.log(`次のコマンドで起動してください:\n  cd "${targetDir}" && claude\n`);
    return;
  }
  const prompt = buildOnboardingPrompt(depts);
  console.log('\n🚀 onboarding のため claude を起動します (plan モードで各部門テンプレを対話仕上げ)\n');
  const child = spawn('claude', [prompt], { stdio: 'inherit', cwd: targetDir });
  child.on('exit', (code) => process.exit(code ?? 0));
  child.on('error', (e) => {
    console.error('claude の起動に失敗しました:', e.message);
    console.log(`手動起動: cd "${targetDir}" && claude`);
    process.exit(1);
  });
}

main().catch((err) => {
  console.error('\n❌ セットアップ中にエラーが発生しました:');
  console.error(err?.stack || err);
  process.exit(1);
});
