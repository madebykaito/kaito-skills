#!/usr/bin/env node
// kaito-today: what needs the founder today, per owner, in the owner's timezone (IST by default).
//
//   kaito-today.mjs [--owner <id>] [--json]   the needs-me-today list: overdue first, then today
//   kaito-today.mjs brief --owner <id>        a short markdown view of the week, for Monday
//   kaito-today.mjs queue add|list|close ...  the same queue commands as kaito-ledger.mjs
//
// --now <ISO with offset> pretends it is that time (tests, dry runs).
// Exit: 0 ok, 1 error, 2 usage, 4 owner not found.
import path from 'node:path';
import {
  EXIT, STALE_CLAIM_MS, STALE_SINCE, DEFAULT_TZ, fail, run, parseArgs, only, openDb, checkOwnerId, readOwner,
  ownerTz, localParts, isoUtc, nowMs, zonedToUtc,
} from './kaito-ledger-lib.mjs';
import { queue } from './kaito-ledger.mjs';

const BUCKETS = ['overdue', 'today', 'undated', 'later'];
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const tzCache = new Map();
const tzOf = (owner) => { if (!tzCache.has(owner)) tzCache.set(owner, ownerTz(owner)); return tzCache.get(owner); };

function dayName(date) {
  const [y, m, d] = date.split('-').map(Number);
  return `${DAYS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()]} ${d} ${MONTHS[m - 1]}`;
}

// collect(db, owner, ms): every open thing that may need the founder, with its local date.
export function collect(db, owner, ms) {
  const items = [];
  const byOwner = owner ? 'AND owner = ?' : '';
  const p = owner ? [owner] : [];
  for (const q of db.prepare(`SELECT * FROM queue_items WHERE state = 'open' ${byOwner}`).all(...p)) {
    items.push({ source: 'queue', id: String(q.id), owner: q.owner, kind: q.kind, title: q.title, due_at: q.due_at, due_date: q.due_date, all_day: !!q.all_day, ref: q.ref });
  }
  for (const a of db.prepare(`SELECT * FROM actions WHERE state = 'proposed' ${byOwner}`).all(...p)) {
    items.push({ source: 'action', id: a.ref, owner: a.owner, kind: 'approve', title: `Approve ${a.action} on ${a.account}`, due_at: a.due_at, all_day: false, ref: a.ref });
  }
  const stale = isoUtc(ms - STALE_CLAIM_MS);
  for (const a of db.prepare(`SELECT a.* FROM actions a
      WHERE (state = 'uncertain' OR (state = 'claimed' AND (SELECT ${STALE_SINCE} FROM attempts t WHERE t.ref = a.ref) <= ?)) ${byOwner}`).all(stale, ...p)) {
    items.push({ source: 'action', id: a.ref, owner: a.owner, kind: 'reconcile', title: `Check whether ${a.action} on ${a.account} went out`, due_at: a.due_at, all_day: false, ref: a.ref });
  }
  for (const it of items) {
    const tz = tzOf(it.owner);
    const today = localParts(ms, tz).date;
    let date = null;
    if (it.due_date) {
      // A whole-day item sorts at the start of its day in the owner's zone.
      date = it.due_local = it.due_date;
      const [y, m, d] = date.split('-').map(Number);
      it.sort_at = isoUtc(zonedToUtc(y, m, d, 0, 0, 0, tz));
    } else if (it.due_at) {
      const l = localParts(Date.parse(it.due_at), tz);
      date = l.date;
      it.due_local = `${l.date} ${l.time}`;
      it.sort_at = it.due_at;
    } else { it.due_local = null; it.sort_at = null; }
    it.bucket = date === null ? 'undated' : date < today ? 'overdue' : date === today ? 'today' : 'later';
  }
  return items;
}

const order = (a, b) => (BUCKETS.indexOf(a.bucket) - BUCKETS.indexOf(b.bucket))
  || String(a.sort_at ?? '').localeCompare(String(b.sort_at ?? ''))
  || (a.source === b.source ? 0 : a.source === 'action' ? -1 : 1)
  || a.owner.localeCompare(b.owner) || a.id.localeCompare(b.id, 'en', { numeric: true });

function today(args) {
  only(args, ['_', 'owner', 'json', 'now']);
  const owner = args.owner ? checkOwnerId(args.owner) : null;
  if (owner && !readOwner(owner)) fail(EXIT.notFound, `owner not found: ${owner}`);
  const ms = nowMs(args);
  const tz = owner ? tzOf(owner) : DEFAULT_TZ;
  const date = localParts(ms, tz).date;
  const db = openDb();
  // Queue items due later are not today's business; actions are, because they block a send.
  const items = collect(db, owner, ms).filter((it) => it.source === 'action' || it.bucket !== 'later').sort(order);
  if (args.json) {
    process.stdout.write(`${JSON.stringify({ date, timezone: tz, items: items.map(({ all_day, sort_at, due_date, ...it }) => it) })}\n`);
    return EXIT.ok;
  }
  process.stdout.write(`Needs you today, ${dayName(date)} ${date.slice(0, 4)} (${tz})\n`);
  if (!items.length) { process.stdout.write('Nothing needs you today.\n'); return EXIT.ok; }
  const w = (s, n) => s.padEnd(n);
  const ow = Math.max(...items.map((i) => i.owner.length));
  const kw = Math.max(...items.map((i) => i.kind.length));
  for (const it of items) {
    const when = it.due_local ? `${dayName(it.due_local.slice(0, 10))}${it.due_local.length > 10 ? ` ${it.due_local.slice(11)}` : ''}` : '-';
    process.stdout.write(`${w(it.bucket, 8)} ${w(when, 16)} ${w(it.owner, ow)}  ${w(it.kind, kw)}  ${it.title}  [${it.source === 'queue' ? `q${it.id}` : it.id}]\n`);
  }
  return EXIT.ok;
}

function brief(args) {
  only(args, ['_', 'owner', 'now']);
  const owner = checkOwnerId(args.owner);
  const rec = readOwner(owner);
  if (!rec) fail(EXIT.notFound, `owner not found: ${owner}`);
  const ms = nowMs(args);
  const tz = tzOf(owner);
  const now = localParts(ms, tz);
  // Monday to Sunday of this week, in the owner's zone.
  const dow = new Date(Date.UTC(now.y, now.m - 1, now.d)).getUTCDay();
  const monday = new Date(Date.UTC(now.y, now.m - 1, now.d - ((dow + 6) % 7)));
  const mondayDate = monday.toISOString().slice(0, 10);
  const sundayDate = new Date(monday.getTime() + 6 * 86400000).toISOString().slice(0, 10);
  const db = openDb();
  const items = collect(db, owner, ms).sort(order);
  const label = (it) => {
    const when = it.due_local ? `${dayName(it.due_local.slice(0, 10))}${it.due_local.length > 10 ? ` ${it.due_local.slice(11)}` : ''}` : 'no date';
    return `- ${when}: ${it.title} (${it.source === 'queue' ? `queue ${it.id}` : `\`${it.id}\``})`;
  };
  // Scheduled sends this week, already approved.
  const weekStart = isoUtc(zonedToUtc(monday.getUTCFullYear(), monday.getUTCMonth() + 1, monday.getUTCDate(), 0, 0, 0, tz));
  const weekEnd = isoUtc(zonedToUtc(monday.getUTCFullYear(), monday.getUTCMonth() + 1, monday.getUTCDate() + 7, 0, 0, 0, tz));
  const scheduled = db.prepare("SELECT * FROM actions WHERE owner = ? AND state = 'approved' AND due_at >= ? AND due_at < ? ORDER BY due_at").all(owner, weekStart, weekEnd)
    .map((a) => { const l = localParts(Date.parse(a.due_at), tz); return { source: 'action', id: a.ref, title: `${a.action} on ${a.account} goes out`, due_local: `${l.date} ${l.time}`, sort_at: a.due_at }; });
  const inWeek = (it) => it.due_local && it.due_local.slice(0, 10) >= now.date && it.due_local.slice(0, 10) <= sundayDate;
  const sections = [
    ['Awaiting your approval', items.filter((i) => i.source === 'action' && i.kind === 'approve')],
    ['Uncertain sends to check', items.filter((i) => i.source === 'action' && i.kind === 'reconcile')],
    ['Overdue', items.filter((i) => i.source === 'queue' && i.bucket === 'overdue')],
    ['Due this week', [...items.filter((i) => i.source === 'queue' && inWeek(i)), ...scheduled].sort((a, b) => a.sort_at.localeCompare(b.sort_at))],
  ];
  const out = [`# Week of ${dayName(mondayDate)} ${mondayDate.slice(0, 4)}: ${rec.name || owner}`, '',
    `Made ${dayName(now.date)} ${now.time} ${tz}. ${sections.map(([h, l]) => `${l.length} ${h.toLowerCase()}`).join(', ')}.`];
  for (const [h, list] of sections) {
    out.push('', `## ${h}`, '');
    out.push(...(list.length ? list.map(label) : ['None.']));
  }
  process.stdout.write(`${out.join('\n')}\n`);
  return EXIT.ok;
}

async function main(argv) {
  const args = parseArgs(argv, { bool: ['json', 'all'] });
  const cmd = args._[0];
  if (cmd === 'brief') return brief(args);
  if (cmd === 'queue') return queue(args);
  if (cmd === 'help' || argv.includes('--help')) {
    process.stdout.write('usage: kaito-today.mjs [--owner <id>] [--json] | brief --owner <id> | queue add|list|close\n');
    return EXIT.ok;
  }
  if (cmd) fail(EXIT.usage, `unknown command: ${cmd}`);
  return today(args);
}

if (path.basename(process.argv[1] ?? '') === 'kaito-today.mjs') await run(main);
