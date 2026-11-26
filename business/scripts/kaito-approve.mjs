#!/usr/bin/env node
// The founder approves in a terminal or creates a short-lived, one-time receipt.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import { randomBytes } from 'node:crypto';
import {
  EXIT, fail, run, parseArgs, only, openDb, tx, event, getAction, verifyAction, artifactPath,
  isSha, readOwner, ownerTz, localParts, isoUtc, tooLate, sha256, dbPath, kaitoHome,
} from './kaito-ledger-lib.mjs';

const RECEIPT_TTL_MS = 5 * 60_000;

function canonicalPath(file) {
  try { return fs.realpathSync(file); }
  catch (error) {
    if (error.code !== 'ENOENT' || file === path.dirname(file)) throw error;
    return path.join(canonicalPath(path.dirname(file)), path.basename(file));
  }
}

function fixtureLedger() {
  if (!process.env.KAITO_HOME) return false;
  const home = path.resolve(kaitoHome());
  const realHome = path.join(os.userInfo().homedir, '.kaito');
  if (home === path.resolve(realHome)) return false;
  try {
    const root = fs.realpathSync(home);
    if (root === canonicalPath(realHome)) return false;
    if (!root.startsWith(canonicalPath('/tmp') + path.sep) &&
        !(process.platform === 'darwin' && /^\/private\/var\/folders\/[^/]+\/[^/]+\/T\//.test(root))) return false;
    const file = fs.realpathSync(dbPath());
    if (file !== path.join(root, 'business', 'ledger.db') || file === canonicalPath(path.join(realHome, 'business', 'ledger.db'))) return false;
    const stat = fs.statSync(file);
    return stat.isFile() && stat.nlink === 1;
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    throw error;
  }
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

function checkedProposal(db, ref, digest) {
  const row = getAction(db, ref);
  if (row.state !== 'proposed') fail(EXIT.human, `refused: ${ref} is ${row.state}, not waiting for approval`);
  if (row.digest !== digest) fail(EXIT.human, 'refused: digest does not match this payload');
  const v = verifyAction(row);
  if (v.problems.length || v.digest !== digest) fail(EXIT.human, 'refused: the stored payload does not match what was proposed');
  if (tooLate(row, Date.now())) fail(EXIT.human, 'refused: more than 24 hours past its due time; propose it again');
}

function approve(db, ref, digest, { receipt, fixture }) {
  tx(db, () => {
    checkedProposal(db, ref, digest);
    const ms = Date.now();
    if (receipt) {
      const used = db.prepare(`UPDATE approval_receipts SET consumed_at = ?
        WHERE token_hash = ? AND ref = ? AND digest = ? AND consumed_at IS NULL AND expires_at > ?`)
        .run(ms, sha256(receipt), ref, digest, ms);
      if (used.changes !== 1) fail(EXIT.human, 'refused: approval receipt is invalid, expired or already used');
    }
    // Keep the existing audit enum. A new prompt approval always has a consumed receipt.
    const via = receipt ? 'prompt' : 'terminal';
    const at = isoUtc(ms);
    const context = { mode: receipt ? 'receipt' : fixture ? 'test-fixture' : 'terminal' };
    db.prepare('INSERT INTO approvals (ref, digest, via, at, context_json) VALUES (?, ?, ?, ?, ?)')
      .run(ref, digest, via, at, JSON.stringify(context));
    db.prepare("UPDATE actions SET state = 'approved', approved_at = ?, approved_via = ?, updated_at = ? WHERE ref = ?")
      .run(at, via, at, ref);
    event(db, ref, 'approved', { via, digest, ...context });
  });
}

function createReceipt(db, ref, digest) {
  const token = randomBytes(32).toString('hex');
  tx(db, () => {
    checkedProposal(db, ref, digest);
    db.prepare('INSERT INTO approval_receipts (token_hash, ref, digest, expires_at) VALUES (?, ?, ?, ?)')
      .run(sha256(token), ref, digest, Date.now() + RECEIPT_TTL_MS);
  });
  process.stdout.write(`receipt=${token}\n`);
}

async function main(argv) {
  const issuing = argv[0] === 'receipt';
  const args = parseArgs(issuing ? argv.slice(1) : argv, { bool: ['show', 'json'] });
  only(args, ['_', 'digest', 'receipt', 'show', 'json']);
  const [ref] = args._;
  if (!ref || args._.length !== 1 || (issuing && Object.keys(args).length !== 1) ||
      (args.receipt !== undefined && (!args.digest || !isSha(args.receipt))) ||
      (args.show && args.digest !== undefined)) {
    fail(EXIT.usage, 'usage: kaito-approve.mjs <ref> [--show | --digest <sha256> --receipt <token>] or receipt <ref>');
  }
  if (args.digest !== undefined && !isSha(args.digest)) fail(EXIT.usage, '--digest takes the full 64-character sha256');
  const fixture = args.digest !== undefined && !args.receipt && process.env.KAITO_TEST_APPROVAL === '1';
  if (fixture && !fixtureLedger()) fail(EXIT.human, 'refused: test approval requires a temporary fixture ledger');
  const db = openDb();
  try {
    const row = getAction(db, ref);
    const { text: shown, v, problems, warnings } = card(row);
    if (args.show) {
      process.stdout.write(args.json ? `${JSON.stringify({ ref, state: row.state, digest: row.digest, payload: v.payload, problems, warnings })}\n` : shown);
      return EXIT.ok;
    }
    if (row.state !== 'proposed') fail(EXIT.human, `refused: ${ref} is ${row.state}, not waiting for approval`);
    if (problems.length) {
      process.stderr.write(shown);
      fail(EXIT.human, 'refused: the stored payload does not match what was proposed');
    }

    if (args.digest !== undefined) {
      if (args.digest !== row.digest) fail(EXIT.human, 'refused: digest does not match this payload');
      if (!args.receipt && !fixture) fail(EXIT.human, 'refused: --digest needs an approval receipt from the founder’s terminal');
    } else {
      if (!process.stdin.isTTY || !process.stdout.isTTY) fail(EXIT.human, 'refused: no terminal. Run this command in the founder’s terminal.');
      process.stdout.write(shown);
      const answer = await askTty(`\nType the first 8 characters of the digest to ${issuing ? 'create a receipt' : 'approve'}, anything else cancels: `);
      if (answer.toLowerCase() !== row.digest.slice(0, 8)) fail(EXIT.human, 'not approved: the typed characters do not match the digest');
    }

    if (issuing) createReceipt(db, ref, row.digest);
    else {
      approve(db, ref, row.digest, { receipt: args.receipt, fixture });
      process.stdout.write(`approved ref=${ref} digest=${row.digest}\n`);
    }
    return EXIT.ok;
  } finally { db.close(); }
}

if (path.basename(process.argv[1] ?? '') === 'kaito-approve.mjs') await run(main);
