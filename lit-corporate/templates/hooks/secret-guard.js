#!/usr/bin/env node
// lit-corporate UserPromptSubmit hook
// Claude Code から stdin で受け取る JSON の prompt フィールドに
// APIキー・パスワード等の機密パターンが含まれていたら exit 2 でブロックする。

const PATTERNS = [
  { name: 'Anthropic APIキー',   re: /sk-ant-[A-Za-z0-9_\-]{20,}/ },
  { name: 'OpenAI APIキー',      re: /\bsk-[A-Za-z0-9]{32,}\b/ },
  { name: 'AWS アクセスキーID',  re: /\bAKIA[0-9A-Z]{16}\b/ },
  { name: 'AWS シークレットキー', re: /aws_secret_access_key\s*[:=]\s*['"]?[A-Za-z0-9/+=]{40}/i },
  { name: 'GitHub PAT',          re: /\bghp_[A-Za-z0-9]{36,}\b/ },
  { name: 'Google APIキー',      re: /\bAIza[0-9A-Za-z_\-]{35}\b/ },
  { name: 'Slack トークン',      re: /\bxox[baprs]-[A-Za-z0-9\-]{10,}\b/ },
  { name: 'Private Key (PEM)',   re: /-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----/ },
  { name: 'APIキー形式',         re: /\bapi[_-]?key\s*[:=]\s*['"]?[A-Za-z0-9_\-]{16,}/i },
  { name: 'パスワード直書き',     re: /\b(?:password|passwd|pwd)\s*[:=]\s*['"]?[^\s'";,]{8,}/i },
  { name: 'Bearer トークン',     re: /\bBearer\s+[A-Za-z0-9_\-.=]{20,}\b/ },
];

function readStdin() {
  return new Promise((resolve) => {
    let buf = '';
    if (process.stdin.isTTY) return resolve('{}');
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (c) => { buf += c; });
    process.stdin.on('end', () => resolve(buf || '{}'));
  });
}

(async () => {
  let data = {};
  try {
    data = JSON.parse(await readStdin() || '{}');
  } catch {
    // パース失敗時は通過させる（誤ブロック回避）
    process.exit(0);
  }

  const prompt = typeof data.prompt === 'string' ? data.prompt : '';
  if (!prompt) process.exit(0);

  const hits = [];
  for (const { name, re } of PATTERNS) {
    if (re.test(prompt)) hits.push(name);
  }

  if (hits.length === 0) process.exit(0);

  const unique = [...new Set(hits)];
  const msg = [
    '',
    '⛔ 機密情報と思われるパターンがプロンプトに含まれています。送信をブロックしました。',
    `検知: ${unique.join(' / ')}`,
    '',
    '対処方法:',
    '  • APIキー・パスワード・秘密鍵はプロンプトに貼り付けないでください',
    '  • 必要な場合は .env やシークレットマネージャ等の外部保管からコードで読み込む形にしてください',
    '  • 誤検知の場合はキーワード表現を変えて再送信してください',
    '',
  ].join('\n');

  process.stderr.write(msg);
  process.exit(2);
})();
