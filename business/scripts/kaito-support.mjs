#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { EXIT, fail, run, parseArgs, only, openDb, tx, isoUtc, sha256 } from './kaito-ledger-lib.mjs';
import { isAddress, isMessageId } from './kaito-email-policy.mjs';
import { resolveMailOwner, readMailKey, runMailPython } from './kaito-mail-runtime.mjs';

const USAGE = 'usage: kaito-support.mjs [triage] [--owner id] (--maildir path | --mbox path | --imap) [--limit 50] [--no-queue]';
const CASES = [
  ['billing', /\b(billing|payment|invoice|refund|charged)\b/i],
  ['delivery', /\b(delivery|shipping|tracking|shipment)\b/i],
  ['account', /\b(account|password|login|sign in)\b/i],
  ['product', /\b(product|damaged|broken|defective)\b/i],
];
const URGENT = /\b(urgent|asap|emergency|fraud|unauthorized|double charged|cannot log in)\b/i;
const normalize = (value) => value.normalize('NFKC').toLowerCase().replace(/[^\p{L}\p{N}\p{M}]+/gu, ' ').trim();
const safeLine = (value) => value.replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu, ' ').replace(/\s+/g, ' ').trim();

function loadFaq(root) {
  let entries;
  try { entries = JSON.parse(fs.readFileSync(path.join(root, 'faq.json'), 'utf8')); } catch (e) {
    if (e.code === 'ENOENT') fail(EXIT.notFound, 'create faq.json in this owner’s folder (use [] for an empty FAQ)');
    fail(EXIT.error, 'cannot read this owner’s faq.json');
  }
  if (!Array.isArray(entries) || entries.some((entry) => !entry
    || typeof entry.category !== 'string' || !/^[a-z][a-z0-9-]{0,31}$/.test(entry.category)
    || !Array.isArray(entry.keywords) || !entry.keywords.length
    || entry.keywords.some((word) => typeof word !== 'string' || !normalize(word))
    || typeof entry.reply !== 'string' || !entry.reply.trim() || entry.reply.includes('\0'))) {
    fail(EXIT.usage, 'faq.json needs entries with category, nonempty keywords and reply');
  }
  return entries.map(({ category, keywords, reply }) => ({
    category, keywords: [...new Set(keywords.map(normalize))], body: reply,
  }));
}

function triage(message, faq) {
  const source = `${message.subject}\n${message.text}`;
  const words = ` ${normalize(source)} `;
  const ranked = faq.map(({ category, keywords, body }) => ({
    category, body, score: keywords.filter((word) => words.includes(` ${word} `)).length,
  })).filter(({ score }) => score > 0).sort((a, b) => b.score - a.score);
  const category = ranked[0]?.category ?? CASES.find(([, test]) => test.test(source))?.[0] ?? 'general';
  const subject = safeLine(message.subject);
  const thread = isMessageId(message.message_id) ? message.message_id : null;
  const customer = message.customer && isAddress(message.customer.email)
    ? { name: safeLine(message.customer.name), email: message.customer.email } : null;
  const reply = isAddress(message.reply_to?.email) ? {
    to: message.reply_to.email,
    subject: /^re:/i.test(subject) ? subject : `Re: ${subject || 'Your message'}`,
    in_reply_to: thread,
  } : null;
  const drafts = ranked.length ? ranked.slice(0, 3) : [
    { category, score: 0, body: 'Thanks for reaching out. Could you share a little more detail so we can look into this?' },
  ];
  return {
    id: thread && customer ? sha256(JSON.stringify([thread, customer.email.toLowerCase()])) : message.fingerprint,
    subject, category, urgency: URGENT.test(source) ? 'high' : 'normal', customer, reply, drafts,
    timestamp: message.timestamp,
  };
}

function enqueue(owner, items) {
  const db = openDb();
  tx(db, () => {
    const find = db.prepare('SELECT queue_id FROM support_inbox_items WHERE owner = ? AND message_key = ?');
    const link = db.prepare('INSERT INTO support_inbox_items VALUES (?, ?, ?)');
    const add = db.prepare(`
      INSERT INTO queue_items (owner, kind, title, due_at, created_at)
      VALUES (?, 'support-reply', ?, ?, ?)
    `);
    const now = isoUtc(Date.now());
    for (const item of items) {
      const known = find.get(owner, item.id);
      if (known) { item.queue_id = known.queue_id; continue; }
      const subject = item.subject.slice(0, 140) || '(no subject)';
      const urgent = item.urgency === 'high' ? 'Urgent ' : '';
      const title = `${urgent}support review: ${subject}`;
      const id = add.run(owner, title, item.urgency === 'high' ? now : null, now).lastInsertRowid;
      link.run(owner, item.id, id);
      item.queue_id = Number(id);
    }
  });
}

await run((argv) => {
  if (argv.length === 1 && ['-h', '--help', 'help'].includes(argv[0])) { console.log(USAGE); return; }
  const args = parseArgs(argv, { bool: ['imap', 'no-queue'] });
  only(args, ['owner', 'maildir', 'mbox', 'imap', 'limit', 'no-queue']);
  const sources = ['maildir', 'mbox', 'imap'].filter((s) => args[s]);
  const limit = args.limit ?? '50';
  if (args._.length > 1 || (args._.length && args._[0] !== 'triage') || sources.length !== 1
      || !/^[1-9][0-9]*$/.test(limit) || Number(limit) > 200) fail(EXIT.usage, USAGE);
  const { owner, root, record } = resolveMailOwner(args.owner);
  const faq = loadFaq(root);
  const [source] = sources;
  const config = source === 'imap' ? readMailKey(record, 'imap') : undefined;
  if (source !== 'imap' && !fs.existsSync(args[source])) fail(EXIT.notFound, 'mail export does not exist');
  const response = runMailPython('kaito-support-read.py', { source, path: args[source], config, limit: Number(limit) }, 60_000);
  if (response.status !== 0) fail(EXIT.error, `could not read ${source} inbox (check configuration and Python 3)`);
  const sorted = JSON.parse(response.stdout).map((message) => triage(message, faq)).sort((a, b) =>
    Number(b.urgency === 'high') - Number(a.urgency === 'high')
    || b.drafts[0].score - a.drafts[0].score || b.timestamp - a.timestamp || a.id.localeCompare(b.id));
  const seen = new Set();
  const items = sorted.filter(({ id }) => {
    if (seen.has(id)) return false;
    seen.add(id);
    return true;
  });
  if (!args['no-queue']) enqueue(owner, items);
  console.log(JSON.stringify({ owner, items }, null, 2));
});
