#!/usr/bin/env node
// lit-corporate statusline
// stdin で Claude Code から JSON を受け取り、2 行のステータスを stdout に出力する。
//
// 1 行目: [ModelName] 5h: ▓▓▓░░░░░░░ 30% | Reset: 18:00 JST   (rate_limits がある場合)
//         [ModelName]                                             (ない場合)
// 2 行目: Context: ██░░░░░░░░ 24% (48k/200k)

const BAR_WIDTH = 10;
const CYAN  = '\x1b[36m';
const GREEN = '\x1b[32m';
const YELL  = '\x1b[33m';
const RED   = '\x1b[31m';
const DIM   = '\x1b[2m';
const RESET = '\x1b[0m';

function readStdin() {
  return new Promise((resolve) => {
    let buf = '';
    if (process.stdin.isTTY) return resolve('{}');
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (c) => { buf += c; });
    process.stdin.on('end', () => resolve(buf || '{}'));
  });
}

function bar(pct, filledChar = '▓', emptyChar = '░') {
  const p = Math.max(0, Math.min(100, Number(pct) || 0));
  const filled = Math.round((p / 100) * BAR_WIDTH);
  return filledChar.repeat(filled) + emptyChar.repeat(BAR_WIDTH - filled);
}

function colorForPct(pct) {
  if (pct >= 90) return RED;
  if (pct >= 70) return YELL;
  return GREEN;
}

function fmtJst(epochSec) {
  if (!Number.isFinite(epochSec) || epochSec <= 0) return null;
  const d = new Date(epochSec * 1000);
  const fmt = new Intl.DateTimeFormat('ja-JP', {
    timeZone: 'Asia/Tokyo',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
  return fmt.format(d);
}

function humanTokens(n) {
  if (!Number.isFinite(n)) return '?';
  if (n >= 1000) return `${Math.round(n / 100) / 10}k`.replace('.0k', 'k');
  return String(n);
}

(async () => {
  let data = {};
  try {
    data = JSON.parse(await readStdin() || '{}');
  } catch {
    data = {};
  }

  const modelName = data?.model?.display_name || data?.model?.id || 'Claude';

  // --- Line 1: model + 5h rate limit ---
  const rl = data?.rate_limits?.five_hour;
  let line1 = `${CYAN}[${modelName}]${RESET}`;

  if (rl && (rl.used_percentage != null || rl.resets_at != null)) {
    const pct = Number(rl.used_percentage ?? 0);
    const c = colorForPct(pct);
    const pctStr = `${pct.toFixed(0).padStart(2, ' ')}%`;
    const parts = [`${c}5h: ${bar(pct)} ${pctStr}${RESET}`];
    const jst = fmtJst(Number(rl.resets_at));
    if (jst) parts.push(`${DIM}Reset: ${jst} JST${RESET}`);
    line1 += ` ${parts.join(' | ')}`;
  }

  // --- Line 2: context window ---
  const ctx = data?.context_window || {};
  const ctxPct = Number(ctx.used_percentage ?? 0);
  const ctxSize = Number(ctx.context_window_size ?? 200000);
  const ctxUsed = Math.round((ctxPct / 100) * ctxSize);
  const ctxColor = colorForPct(ctxPct);
  const line2 =
    `${ctxColor}Context: ${bar(ctxPct, '█', '░')} ${ctxPct.toFixed(0).padStart(2, ' ')}%${RESET} ` +
    `${DIM}(${humanTokens(ctxUsed)}/${humanTokens(ctxSize)})${RESET}`;

  process.stdout.write(line1 + '\n' + line2 + '\n');
})();
