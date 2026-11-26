#!/usr/bin/env node
// kaito-approve: the founder's yes on one exact payload.
//
//   kaito-approve.mjs <ref>                    in the founder's own terminal: shows the payload and
//                                              asks for the first 8 characters of its digest
//   kaito-approve.mjs <ref> --digest <sha256>  as a command the host shows in its permission prompt
//   kaito-approve.mjs <ref> --show             print the payload card only, approve nothing
//
// An agent never runs this on its own. It runs the --digest form only after the founder said
// yes in chat to that ref, and the host then asks the founder again in its permission prompt.
// What this script can and cannot enforce is in business/references/ledger.md.
// Exit: 0 approved (or shown), 1 error, 2 usage, 3 refused or not approved, 4 not found.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import { execFileSync } from 'node:child_process';
import {
  EXIT, fail, run, parseArgs, only, openDb, tx, event, getAction, verifyAction, artifactPath,
  isSha, readOwner, ownerTz, localParts, isoUtc, tooLate, sha256,
} from './kaito-ledger-lib.mjs';

const SELF = (() => { try { return fs.realpathSync(process.argv[1]); } catch { return process.argv[1] ?? 'kaito-approve.mjs'; } })();

// ---------- who is running us ----------
// Environment variables that agent hosts set in the shells they run.
const AGENT_ENV = ['CLAUDECODE', 'CLAUDE_CODE_ENTRYPOINT', 'AI_AGENT', 'CODEX_SANDBOX', 'CODEX_THREAD_ID', 'CODEX_CI',
  'CODEX_SANDBOX_NETWORK_DISABLED', 'GEMINI_CLI', 'OPENCODE', 'CURSOR_AGENT', 'CURSOR_TRACE_ID', 'AIDER_MODEL', 'GOOSE_PROVIDER', 'AMP_API_KEY'];
const CODEX_ENV = ['CODEX_SANDBOX', 'CODEX_THREAD_ID', 'CODEX_CI', 'CODEX_SANDBOX_NETWORK_DISABLED'];
const AGENT_BIN = /^(claude|codex|codex-[a-z0-9-]+|gemini|opencode|cursor-agent|aider|goose|amp)$/;
const AGENT_ARGS = /@anthropic-ai\/claude-code|\/claude-code\/cli|@openai\/codex|\/codex\/bin\//;

// ancestors(): [{pid, comm, args}] from our parent up to init. Best effort; [] when unknown.
export function ancestors() {
  const out = [];
  const seen = new Set();
  let table = null;
  const procInfo = (pid) => {
    if (fs.existsSync('/proc/self/stat')) {
      try {
        const stat = fs.readFileSync(`/proc/${pid}/stat`, 'utf8');
        const ppid = +stat.slice(stat.lastIndexOf(')') + 2).split(' ')[1];
        const args = fs.readFileSync(`/proc/${pid}/cmdline`, 'utf8').split('\0').filter(Boolean);
        let comm = args[0] ?? '';
        try { comm = fs.readlinkSync(`/proc/${pid}/exe`); } catch { /* not ours to read */ }
        return { ppid, comm, args: args.join(' ') };
      } catch { return null; }
    }
    if (!table) {
      table = new Map();
      try {
        const comms = execFileSync('ps', ['-axo', 'pid=,ppid=,comm='], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
        for (const l of comms.split('\n')) { const m = l.match(/^\s*(\d+)\s+(\d+)\s+(.*)$/); if (m) table.set(+m[1], { ppid: +m[2], comm: m[3], args: '' }); }
        const args = execFileSync('ps', ['-axww', '-o', 'pid=,args='], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
        for (const l of args.split('\n')) { const m = l.match(/^\s*(\d+)\s+(.*)$/); if (m && table.has(+m[1])) table.get(+m[1]).args = m[2]; }
      } catch { /* no ps */ }
    }
    return table.get(pid) ?? null;
  };
  let pid = process.ppid;
  while (pid > 1 && !seen.has(pid) && out.length < 64) {
    seen.add(pid);
    const p = procInfo(pid);
    if (!p) break;
    out.push({ pid, comm: p.comm, args: p.args });
    pid = p.ppid;
  }
  return out;
}

// agentSigns(): reasons to think an agent, not a person, started this process.
export function agentSigns(chain = ancestors()) {
  const signs = AGENT_ENV.filter((k) => process.env[k]).map((k) => `environment variable ${k} is set`);
  for (const p of chain) {
    const names = procNames(p);
    if (names.some((n) => AGENT_BIN.test(n)) || AGENT_ARGS.test(p.args || '')) { signs.push(`started under ${names[0]} (pid ${p.pid})`); break; }
  }
  return signs;
}

// procNames(p): the executable's name and the name it was started as (a renamed or linked
// binary shows up as one or the other, depending on the system).
const procNames = (p) => [path.basename(p.comm || ''), path.basename((p.args || '').split(' ')[0] || '')].filter(Boolean);

// ---------- would a host run this without asking? ----------
// The --digest path only means something when the host stops and shows the founder this
// command. These checks look for the common ways it would not. They are best effort.
const BYPASS_ARGS = [
  [/(^|\s)--dangerously-skip-permissions(\s|$)/, 'the agent runs with --dangerously-skip-permissions'],
  [/(^|\s)--permission-mode[= ](bypassPermissions|auto|dontAsk)(\s|$)/, 'the agent runs in a permission mode that does not ask'],
  [/(^|\s)--dangerously-bypass-approvals-and-sandbox(\s|$)/, 'codex runs with --dangerously-bypass-approvals-and-sandbox'],
  [/(^|\s)--yolo(\s|$)/, 'the agent runs with --yolo'],
  [/(^|\s)--full-auto(\s|$)/, 'codex runs with --full-auto'],
  [/(^|\s)(-a|--ask-for-approval)[= ]never(\s|$)/, 'codex runs with approvals set to never'],
  [/(^|\/|\s)codex(\.js)?\s+(exec|e)(\s|$)/, 'codex exec does not ask before running commands'],
];

function readJson(f) {
  try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return null; }
}

// Claude Code allow rules: Bash, Bash(*), Bash(prefix:*), Bash(glob).
function ruleMatches(rule, commands) {
  if (typeof rule !== 'string') return false;
  if (rule === 'Bash' || rule === 'Bash(*)' || rule === 'Bash(**)') return true;
  const m = rule.match(/^Bash\((.*)\)$/s);
  if (!m) return false;
  let pat = m[1];
  if (pat.endsWith(':*')) pat = `${pat.slice(0, -2)}*`;
  const re = new RegExp(`^${pat.split('*').map((s) => s.replace(/[.+?^${}()|[\]\\]/g, '\\$&')).join('.*')}$`, 's');
  return commands.some((c) => re.test(c));
}

function settingsFiles(cwd) {
  const home = os.homedir();
  const files = [path.join(home, '.claude', 'settings.json'), path.join(home, '.claude', 'settings.local.json')];
  for (let d = path.resolve(cwd); ; d = path.dirname(d)) {
    files.push(path.join(d, '.claude', 'settings.json'), path.join(d, '.claude', 'settings.local.json'));
    if (d === path.dirname(d) || d === home) break;
  }
  if (process.platform === 'darwin') files.push('/Library/Application Support/ClaudeCode/managed-settings.json');
  else files.push('/etc/claude-code/managed-settings.json');
  return files;
}

export function autoRunHazards(ref, digest, chain = ancestors()) {
  const hazards = [];
  for (const p of chain) for (const [re, why] of BYPASS_ARGS) if (re.test(p.args || '')) hazards.push(why);
  const home = os.homedir();
  const tildeSelf = SELF.startsWith(`${home}/`) ? `~/${SELF.slice(home.length + 1)}` : SELF;
  const tail = `${ref} --digest ${digest}`;
  const paths = [...new Set([SELF, tildeSelf, process.argv[1], path.resolve(process.argv[1])])];
  const commands = [...paths.flatMap((p) => [`node ${p} ${tail}`, `${p} ${tail}`]), `kaito-approve ${tail}`, `node kaito-approve.mjs ${tail}`];
  for (const f of settingsFiles(process.cwd())) {
    const s = readJson(f);
    if (!s || typeof s !== 'object') continue;
    const mode = s.permissions?.defaultMode;
    if (['bypassPermissions', 'auto', 'dontAsk'].includes(mode)) hazards.push(`${f} sets permissions.defaultMode to ${mode}`);
    for (const r of Array.isArray(s.permissions?.allow) ? s.permissions.allow : []) {
      if (ruleMatches(r, commands)) hazards.push(`${f} has an allow rule covering this command`);
    }
  }
  const underCodex = CODEX_ENV.some((k) => process.env[k])
    || chain.some((p) => procNames(p).some((n) => /^codex/.test(n)) || /@openai\/codex/.test(p.args || ''));
  if (underCodex) {
    const toml = (() => { try { return fs.readFileSync(path.join(process.env.CODEX_HOME || path.join(home, '.codex'), 'config.toml'), 'utf8'); } catch { return ''; } })();
    if (/^\s*approval_policy\s*=\s*"never"/m.test(toml)) hazards.push('codex config.toml sets approval_policy = "never"');
    // Saved command rules: prefix_rule(pattern = ["node", ...], decision = "allow").
    const rulesDir = path.join(process.env.CODEX_HOME || path.join(home, '.codex'), 'rules');
    let files = [];
    try { files = fs.readdirSync(rulesDir).filter((f) => f.endsWith('.rules')).map((f) => path.join(rulesDir, f)); } catch { /* none */ }
    const nodes = ['node', process.execPath, path.basename(process.execPath)];
    const scripts = [...paths, path.relative(process.cwd(), SELF), path.basename(SELF)];
    const argvs = scripts.flatMap((p) => [...nodes.map((n) => [n, p, ref, '--digest', digest]), [p, ref, '--digest', digest]]);
    for (const f of files) {
      const text = fs.readFileSync(f, 'utf8');
      for (const m of text.matchAll(/prefix_rule\(([^)]*)\)/g)) {
        if (!/decision\s*=\s*"allow"/.test(m[1])) continue;
        const pm = m[1].match(/pattern\s*=\s*\[([^\]]*)\]/);
        if (!pm) continue;
        const tokens = [...pm[1].matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((t) => t[1]);
        if (tokens.length && argvs.some((a) => tokens.every((t, i) => a[i] === t))) hazards.push(`${f} has an allow rule covering this command`);
      }
    }
  }
  return [...new Set(hazards)];
}

// ---------- the card ----------
// Characters that could move the cursor, erase the screen or reorder text on a terminal are
// shown as \u{...} so the card cannot be made to hide or overwrite part of itself. ZWJ and
// ZWNJ stay: Bengali and other Indic scripts need them.
const UNSAFE = /[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u061c\u200e\u200f\u2028\u2029\u202a-\u202e\u2066-\u2069\ufeff\ufff9-\ufffb]/g;
export const escapeForTerminal = (s) => s.replace(UNSAFE, (c) => `\\u{${c.codePointAt(0).toString(16).padStart(4, '0')}}`);

// card(row): the payload as the founder sees it, rendered from the same bytes it hashes.
function card(row) {
  const problems = [];  // the payload cannot be shown or does not match: never approvable
  const warnings = [];  // shown, but worth a second look
  const read = (sha, label) => {
    let buf = null;
    try { buf = fs.readFileSync(artifactPath(sha)); } catch { problems.push(`${label} file is missing from the artifact store`); return null; }
    if (sha256(buf) !== sha) { problems.push(`${label} file changed after it was stored`); return null; }
    return buf;
  };
  const owner = readOwner(row.owner);
  const tz = ownerTz(row.owner);
  const lines = [];
  lines.push('kaito-approve: read every line before you say yes.', '');
  lines.push(`ref:        ${row.ref}`);
  lines.push(`owner:      ${row.owner}${owner?.name ? ` (${escapeForTerminal(String(owner.name))})` : ''}`);
  lines.push(`account:    ${escapeForTerminal(row.account)}`);
  lines.push(`action:     ${row.action}`);
  if (row.due_at) {
    const p = localParts(Date.parse(row.due_at), tz);
    lines.push(`due:        ${p.date} ${p.time} ${tz} (${row.due_at})`);
  } else lines.push('due:        none (sent when claimed)');
  lines.push(`disclosure: ${row.disclosure === 'ai' ? 'ai (labelled as AI-generated)' : 'none (no AI label)'}`);
  const media = JSON.parse(row.media_json);
  if (media.length) {
    lines.push(`media:      ${media.length} file${media.length > 1 ? 's' : ''}, in this order`);
    media.forEach((sha, i) => {
      const buf = read(sha, `media ${i + 1}`);
      lines.push(`  ${i + 1}. sha256 ${sha}  ${buf ? buf.length : '?'} bytes  ${artifactPath(sha)}`);
    });
  } else lines.push('media:      none');
  if (row.text_sha256) {
    const buf = read(row.text_sha256, 'text');
    const text = buf ? buf.toString('utf8') : '';
    const body = text.endsWith('\n') ? text.slice(0, -1) : text;
    const unsafe = (text.match(UNSAFE) || []).length;
    lines.push(`text:       sha256 ${row.text_sha256}, ${buf ? buf.length : '?'} bytes, each line after "| ":`);
    lines.push(...body.split('\n').map((l) => `| ${escapeForTerminal(l)}`));
    if (unsafe) warnings.push(`the text holds ${unsafe} control or direction character${unsafe > 1 ? 's' : ''}, shown as \\u{...}; they are sent as they are`);
  } else lines.push('text:       none');
  const v = verifyAction(row);
  for (const p of v.problems) if (!problems.includes(p)) problems.push(p);
  lines.push('', `digest:     ${row.digest}`);
  if (problems.length || warnings.length) lines.push('', ...[...problems, ...warnings].map((p) => `PROBLEM: ${p}`));
  return { text: `${lines.join('\n')}\n`, v, problems, warnings };
}

function askTty(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    let done = false;
    rl.on('close', () => { if (!done) resolve(''); });
    rl.question(question, (a) => { done = true; rl.close(); resolve(a.trim()); });
  });
}

function approve(db, ref, digest, via, context) {
  return tx(db, () => {
    const row = getAction(db, ref);
    if (row.state !== 'proposed') return `refused: ${ref} is ${row.state}, not waiting for approval`;
    const v = verifyAction(row);
    if (v.problems.length || v.digest !== row.digest) return `refused: payload changed since it was proposed (${v.problems.join('; ')})`;
    if (digest !== row.digest) return 'refused: digest does not match this payload';
    if (tooLate(row, Date.now())) return 'refused: more than 24 hours past its due time; propose it again';
    const at = isoUtc(Date.now());
    db.prepare('INSERT INTO approvals (ref, digest, via, at, context_json) VALUES (?, ?, ?, ?, ?)').run(ref, digest, via, at, JSON.stringify(context));
    db.prepare("UPDATE actions SET state = 'approved', approved_at = ?, approved_via = ?, updated_at = ? WHERE ref = ? AND state = 'proposed'").run(at, via, at, ref);
    event(db, ref, 'approved', { via, digest });
    return null;
  });
}

async function main(argv) {
  const args = parseArgs(argv, { bool: ['show', 'json'] });
  only(args, ['_', 'digest', 'show', 'json']);
  const ref = args._[0];
  if (!ref || args._.length > 1) fail(EXIT.usage, 'usage: kaito-approve.mjs <ref> [--digest <sha256> | --show]');
  if (args.digest !== undefined && !isSha(args.digest)) {
    fail(EXIT.usage, '--digest takes the full 64-character sha256 written out on the command line (no files, no prefixes)');
  }
  const db = openDb();
  const row = getAction(db, ref);
  const { text: shown, v, problems, warnings } = card(row);

  if (args.show) {
    if (args.json) process.stdout.write(`${JSON.stringify({ ref, state: row.state, digest: row.digest, payload: v.payload, problems, warnings })}\n`);
    else process.stdout.write(shown);
    return EXIT.ok;
  }
  if (row.state !== 'proposed') fail(EXIT.human, `refused: ${ref} is ${row.state}, not waiting for approval`);
  if (problems.length || v.problems.length) { process.stderr.write(shown); fail(EXIT.human, 'refused: the stored payload does not match what was proposed'); }

  const chain = ancestors();
  const context = {
    uid: process.getuid?.(), tty: process.stdin.isTTY ? (process.env.TTY || 'yes') : null,
    parents: chain.slice(0, 6).map((p) => path.basename(p.comm || '?')),
  };

  if (args.digest !== undefined) {
    // Path (b): a command line the host showed the founder in its permission prompt. With no
    // terminal and no agent host above us, no one was shown a prompt (a cron job, a script).
    // Only an agent host shows a permission prompt. Run from a plain terminal or a script,
    // nobody was asked, so the founder uses the typed-prefix path instead.
    if (!agentSigns(chain).length) {
      fail(EXIT.human, 'refused: --digest is only for a command an agent host shows in its permission prompt, and no agent host is running this. The founder runs kaito-approve.mjs <ref> and types the digest prefix.');
    }
    const hazards = autoRunHazards(ref, args.digest, chain);
    if (hazards.length) {
      process.stderr.write(`${hazards.map((h) => `  ${h}`).join('\n')}\n`);
      fail(EXIT.human, 'refused: this command could run without the founder seeing a permission prompt. The founder approves in their own terminal instead: kaito-approve.mjs <ref>');
    }
    process.stdout.write(shown);
    const err = approve(db, ref, args.digest, 'prompt', context);
    if (err) fail(EXIT.human, err);
    process.stdout.write(`approved ref=${ref} digest=${row.digest}\n`);
    return EXIT.ok;
  }

  // Path (a): the founder at a real terminal types the digest prefix.
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    fail(EXIT.human, 'refused: no terminal. The founder runs kaito-approve in their own terminal, or approves the --digest command in the host permission prompt. An agent never approves on its own.');
  }
  const signs = agentSigns(chain);
  if (signs.length) {
    process.stderr.write(`${signs.map((s) => `  ${s}`).join('\n')}\n`);
    fail(EXIT.human, 'refused: this terminal belongs to an agent session. Run kaito-approve in your own terminal app.');
  }
  process.stdout.write(shown);
  const answer = await askTty('\nType the first 8 characters of the digest to approve, anything else cancels: ');
  if (answer.toLowerCase() !== row.digest.slice(0, 8)) fail(EXIT.human, 'not approved: the typed characters do not match the digest');
  const err = approve(db, ref, row.digest, 'terminal', context);
  if (err) fail(EXIT.human, err);
  process.stdout.write(`approved ref=${ref} digest=${row.digest}\n`);
  return EXIT.ok;
}

if (path.basename(process.argv[1] ?? '') === 'kaito-approve.mjs') await run(main);
