#!/usr/bin/env node
// kaito-ledger: the approval ledger. Proposes actions with their payload, hands an approved
// action to exactly one publisher (claim), records what happened, and keeps the today queue.
// There is no approve command here on purpose: the founder's yes comes from kaito-approve.
// Exit: 0 ok, 1 error, 2 usage, 3 needs a human (not approved, digest differs, already claimed), 4 not found.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {
  EXIT, STATES, STALE_CLAIM_MS, Fail, fail, run, parseArgs, only, openDb, migrate, tx, event, getAction,
  verifyAction, putArtifact, artifactPath, canonicalText, payloadOf, digestOf, isSha, readOwner,
  checkOwnerId, ownerTz, parseWhen, isoUtc, nowMs, tooLate, printKv, localParts, dbPath,
} from './kaito-ledger-lib.mjs';

const USAGE = `usage: kaito-ledger.mjs <command>
  propose --owner <id> --account <handle> --action <verb> [--text-file f] [--media f ...] [--disclosure ai|none] [--due <when>] [--json]
  status <ref> [--json]
  list [--owner <id>] [--state <s>] [--due-before <when>] [--json]
  claim <ref> --digest <sha256> [--json]
  record <ref> --attempt <n> --result ok|failed|uncertain [--remote-id x] [--note text]
  reconcile [--owner <id>] [--json]
  reconcile <ref> --sent --remote-id <x> | --failed [--note text]
  reject <ref> [--note text]
  expire
  migrate
  queue add --owner <id> --kind <kind> --title <text> [--due <when>] [--ref <ref>] [--note text]
  queue list [--owner <id>] [--all] [--json]
  queue close <id>`;

const ACTION_VERB = /^[a-z][a-z0-9._-]{0,63}$/;
const KIND = /^[a-z][a-z0-9-]{0,31}$/;

function newRef(db) {
  for (;;) {
    const ref = `act-${isoUtc(Date.now()).slice(0, 10).replace(/-/g, '')}-${crypto.randomBytes(4).toString('hex')}`;
    if (!db.prepare('SELECT 1 FROM actions WHERE ref = ?').get(ref)) return ref;
  }
}

function readFileArg(f, label) {
  let st;
  try { st = fs.statSync(f); } catch { fail(EXIT.notFound, `${label} not found: ${f}`); }
  if (!st.isFile()) fail(EXIT.usage, `${label} is not a file: ${f}`);
  return fs.readFileSync(f);
}

function propose(args) {
  only(args, ['_', 'owner', 'account', 'action', 'text-file', 'media', 'disclosure', 'due', 'json']);
  const owner = checkOwnerId(args.owner);
  const account = args.account;
  if (!account || account.length > 128 || /[\u0000-\u001f\u007f]/.test(account)) fail(EXIT.usage, 'propose needs --account <handle>');
  if (!args.action || !ACTION_VERB.test(args.action)) fail(EXIT.usage, 'propose needs --action <verb> (lowercase, for example instagram.reel.publish)');
  const disclosure = args.disclosure ?? 'none';
  if (!['ai', 'none'].includes(disclosure)) fail(EXIT.usage, '--disclosure is ai or none');
  if (!args['text-file'] && !args.media?.length) fail(EXIT.usage, 'propose needs --text-file or --media');

  const rec = readOwner(owner);
  if (!rec) fail(EXIT.notFound, `owner not found: ${owner} (no owner.json)`);
  const accounts = rec.channels && typeof rec.channels === 'object' ? Object.values(rec.channels).filter((v) => typeof v === 'string') : [];
  if (!accounts.includes(account)) fail(EXIT.human, `account ${account} is not one of ${owner}'s channels in owner.json`);

  let due_at = null;
  if (args.due) {
    const w = parseWhen(args.due, ownerTz(owner));
    if (w.allDay) fail(EXIT.usage, '--due for an action needs a time, not only a date');
    due_at = isoUtc(w.ms);
  }

  // Read and store every file before touching the database, so the row only names stored bytes.
  const text = args['text-file'] ? canonicalText(readFileArg(args['text-file'], 'text file')) : null;
  const mediaBufs = (args.media ?? []).map((f) => ({ f, buf: readFileArg(f, 'media file') }));
  const textSha = text ? putArtifact(text) : null;
  const media = mediaBufs.map(({ f, buf }) => ({ f, sha: putArtifact(buf), bytes: buf.length }));

  const db = openDb();
  const at = isoUtc(Date.now());
  const r = tx(db, () => {
    // INSERT ... SELECT ... WHERE NOT EXISTS inserts nothing for a known file, so the
    // no-replace trigger only fires on a real second insert.
    const ins = db.prepare('INSERT INTO artifacts (sha256, bytes, kind, name, created_at) SELECT ?, ?, ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM artifacts WHERE sha256 = ?)');
    if (textSha) ins.run(textSha, text.length, 'text', path.basename(args['text-file']), at, textSha);
    for (const m of media) ins.run(m.sha, m.bytes, 'media', path.basename(m.f), at, m.sha);
    const ref = newRef(db);
    const row = { ref, owner, account, action: args.action, disclosure, due_at };
    const payload = payloadOf(row, textSha ? { sha256: textSha, bytes: text.length } : null, media.map((m) => ({ sha256: m.sha, bytes: m.bytes })));
    const digest = digestOf(payload);
    db.prepare(`INSERT INTO actions (ref, owner, account, action, text_sha256, media_json, disclosure, due_at, payload_json, digest, state, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'proposed', ?, ?)`).run(ref, owner, account, args.action, textSha, JSON.stringify(media.map((m) => m.sha)), disclosure, due_at, JSON.stringify(payload), digest, at, at);
    event(db, ref, 'proposed', { digest });
    return { ref, digest };
  });
  if (args.json) process.stdout.write(`${JSON.stringify(r)}\n`);
  else printKv(r);
  return EXIT.ok;
}

function describe(db, row) {
  const v = verifyAction(row);
  const attempt = db.prepare('SELECT * FROM attempts WHERE ref = ? ORDER BY n DESC LIMIT 1').get(row.ref);
  return {
    ref: row.ref, state: row.state, owner: row.owner, account: row.account, action: row.action,
    digest: row.digest, disclosure: row.disclosure, due_at: row.due_at,
    text: row.text_sha256 ? artifactPath(row.text_sha256) : null, text_sha256: row.text_sha256,
    media: JSON.parse(row.media_json).map(artifactPath), media_sha256: JSON.parse(row.media_json),
    approved_at: row.approved_at, approved_via: row.approved_via,
    attempt: attempt?.n ?? null, attempt_result: attempt?.result ?? null,
    remote_id: row.remote_id, intact: v.problems.length === 0, problems: v.problems,
  };
}

function status(args) {
  only(args, ['_', 'json']);
  const db = openDb();
  const d = describe(db, getAction(db, args._[1]));
  if (args.json) process.stdout.write(`${JSON.stringify(d)}\n`);
  else printKv({ ...d, media_sha256: undefined, intact: d.intact ? 'yes' : 'no', problem: d.problems, problems: undefined });
  return EXIT.ok;
}

function list(args) {
  only(args, ['_', 'owner', 'state', 'due-before', 'json']);
  const where = [], params = [];
  if (args.owner) { where.push('owner = ?'); params.push(checkOwnerId(args.owner)); }
  if (args.state) {
    if (!STATES.includes(args.state)) fail(EXIT.usage, `unknown state: ${args.state}`);
    where.push('state = ?'); params.push(args.state);
  }
  if (args['due-before']) {
    const w = parseWhen(args['due-before'], ownerTz(args.owner));
    where.push('due_at IS NOT NULL AND due_at <= ?'); params.push(isoUtc(w.ms));
  }
  const db = openDb();
  const rows = db.prepare(`SELECT ref, state, owner, account, action, due_at, digest FROM actions ${where.length ? `WHERE ${where.join(' AND ')}` : ''} ORDER BY coalesce(due_at, created_at), ref`).all(...params);
  if (args.json) process.stdout.write(`${JSON.stringify(rows)}\n`);
  else for (const r of rows) process.stdout.write(`${r.ref}\t${r.state}\t${r.owner}\t${r.account}\t${r.action}\t${r.due_at ?? '-'}\n`);
  return EXIT.ok;
}

// claim: the one gate before a send. Atomic: two publishers racing for the same ref get one
// winner. Refuses unless the action is approved, the stored files still hash to what was
// approved, and the caller names that same digest.
function claim(args) {
  only(args, ['_', 'digest', 'json']);
  if (!isSha(args.digest)) fail(EXIT.usage, 'claim needs --digest <full 64-character sha256>');
  const db = openDb();
  const ref = args._[1];
  const out = tx(db, () => {
    const ms = Date.now();  // read the clock after taking the lock
    const row = getAction(db, ref);
    const refuse = (why) => { event(db, ref, 'claim-refused', why); return { refused: why }; };
    if (row.state !== 'approved') {
      return refuse(row.state === 'proposed' ? 'not approved' : `already ${row.state}; a ref is claimed once and never again`);
    }
    if (db.prepare('SELECT 1 FROM attempts WHERE ref = ?').get(ref)) return refuse('this ref already has an attempt; a ref is claimed once and never again');
    const v = verifyAction(row);
    if (v.problems.length) return refuse(`payload changed: ${v.problems.join('; ')}`);
    const approval = db.prepare('SELECT digest FROM approvals WHERE ref = ? ORDER BY id DESC LIMIT 1').get(ref);
    if (!approval || approval.digest !== row.digest) return refuse('no approval on record for this payload');
    if (v.digest !== approval.digest) return refuse('payload changed since approval');
    if (args.digest !== approval.digest) return refuse('digest differs from the approved digest');
    if (row.due_at && ms < Date.parse(row.due_at)) return refuse(`not due yet: due ${row.due_at}`);
    if (tooLate(row, ms)) {
      db.prepare("UPDATE actions SET state = 'expired', updated_at = ? WHERE ref = ?").run(isoUtc(ms), ref);
      event(db, ref, 'expired', 'claimed more than 24 hours after its due time');
      return { refused: 'expired: more than 24 hours past its due time' };
    }
    const upd = db.prepare("UPDATE actions SET state = 'claimed', updated_at = ? WHERE ref = ? AND state = 'approved'").run(isoUtc(ms), ref);
    if (upd.changes !== 1) return refuse('lost the race to another claim');
    db.prepare('INSERT INTO attempts (ref, n, digest, claimed_at) VALUES (?, 1, ?, ?)').run(ref, row.digest, isoUtc(ms));
    const d = describe(db, { ...row, state: 'claimed' });
    if (!d.intact) throw new Fail(EXIT.human, `refused: payload changed during claim: ${d.problems.join('; ')}`);  // rolls back
    event(db, ref, 'claimed', { attempt: 1 });
    return { ok: d, n: 1 };
  });
  if (out.refused) fail(EXIT.human, `refused: ${out.refused}`);
  const d = out.ok;
  const r = { ref: d.ref, attempt: out.n, digest: d.digest, idempotency_key: d.ref, owner: d.owner, account: d.account, action: d.action, disclosure: d.disclosure, due_at: d.due_at, text: d.text, text_sha256: d.text_sha256, media: d.media, media_sha256: d.media_sha256 };
  if (args.json) process.stdout.write(`${JSON.stringify(r)}\n`);
  else printKv({ ...r, media_sha256: undefined });
  return EXIT.ok;
}

function record(args) {
  only(args, ['_', 'attempt', 'result', 'remote-id', 'note']);
  const n = Number(args.attempt);
  if (!Number.isSafeInteger(n) || n < 1) fail(EXIT.usage, 'record needs --attempt <n>');
  const result = args.result;
  if (!['ok', 'failed', 'uncertain'].includes(result)) fail(EXIT.usage, '--result is ok, failed or uncertain');
  const state = { ok: 'sent', failed: 'failed', uncertain: 'uncertain' }[result];
  const db = openDb();
  const ref = args._[1];
  const out = tx(db, () => {
    const row = getAction(db, ref);
    const a = db.prepare('SELECT * FROM attempts WHERE ref = ? AND n = ?').get(ref, n);
    if (!a) return { err: [EXIT.notFound, `no attempt ${n} for ${ref}`] };
    const at = isoUtc(Date.now());
    // The publisher was paused past the stale window, reconcile marked it failed, and now it
    // reports the send went through. Believe the later, better evidence.
    if (row.state === 'failed' && a.result === 'uncertain' && result === 'ok') {
      db.prepare('UPDATE attempts SET note = coalesce(note, \'\') || ? WHERE ref = ? AND n = ?').run(` late ok ${at}`, ref, n);
      db.prepare("UPDATE actions SET state = 'reconciled', remote_id = coalesce(?, remote_id), updated_at = ? WHERE ref = ?").run(args['remote-id'] ?? null, at, ref);
      event(db, ref, 'late-ok', { attempt: n, remote_id: args['remote-id'] ?? null });
      return { state: 'reconciled' };
    }
    if (a.result || row.state !== 'claimed') return { err: [EXIT.human, `attempt ${n} of ${ref} is already recorded (${a.result ?? row.state}); use reconcile`] };
    db.prepare('UPDATE attempts SET result = ?, remote_id = ?, note = ?, finished_at = ? WHERE ref = ? AND n = ?').run(result, args['remote-id'] ?? null, args.note ?? null, at, ref, n);
    db.prepare('UPDATE actions SET state = ?, remote_id = coalesce(?, remote_id), updated_at = ? WHERE ref = ?').run(state, args['remote-id'] ?? null, at, ref);
    event(db, ref, `recorded-${result}`, { attempt: n, remote_id: args['remote-id'] ?? null });
    return { state };
  });
  if (out.err) fail(...out.err);
  printKv({ ref, state: out.state });
  return EXIT.ok;
}

// reconcile: with no ref, list what needs a check on the platform: uncertain sends and claims
// that never reported back. With a ref, settle it after that check.
function reconcile(args) {
  only(args, ['_', 'owner', 'json', 'sent', 'failed', 'remote-id', 'note', 'now']);
  const db = openDb();
  const ref = args._[1];
  if (!ref) {
    const ms = nowMs(args);
    const stale = isoUtc(ms - STALE_CLAIM_MS);
    const rows = db.prepare(`SELECT a.ref, a.state, a.owner, a.account, a.action, a.due_at, t.n AS attempt, t.claimed_at
      FROM actions a LEFT JOIN attempts t ON t.ref = a.ref AND t.n = (SELECT max(n) FROM attempts WHERE ref = a.ref)
      WHERE (a.state = 'uncertain' OR (a.state = 'claimed' AND t.claimed_at <= ?)) ${args.owner ? 'AND a.owner = ?' : ''}
      ORDER BY t.claimed_at, a.ref`).all(stale, ...(args.owner ? [checkOwnerId(args.owner)] : []));
    if (args.json) process.stdout.write(`${JSON.stringify(rows)}\n`);
    else for (const r of rows) process.stdout.write(`${r.ref}\t${r.state === 'claimed' ? 'stale-claim' : r.state}\t${r.owner}\t${r.account}\t${r.action}\tattempt ${r.attempt}\t${r.claimed_at}\n`);
    return EXIT.ok;
  }
  if (!!args.sent === !!args.failed) fail(EXIT.usage, 'reconcile <ref> needs --sent --remote-id <x> or --failed');
  if (args.sent && !args['remote-id']) fail(EXIT.usage, 'reconcile --sent needs --remote-id: find the post on the platform first');
  if (args.now) fail(EXIT.usage, '--now is for the list only');
  const ms = Date.now();
  const out = tx(db, () => {
    const row = getAction(db, ref);
    const a = db.prepare('SELECT * FROM attempts WHERE ref = ? ORDER BY n DESC LIMIT 1').get(ref);
    const at = isoUtc(Date.now());
    if (row.state === 'claimed') {
      if (!a || Date.parse(a.claimed_at) > ms - STALE_CLAIM_MS) return { err: [EXIT.human, `${ref} is claimed and may still be sending; wait for its record or for it to go stale`] };
      db.prepare("UPDATE attempts SET result = 'uncertain', finished_at = ?, note = 'no result recorded' WHERE ref = ? AND n = ?").run(at, ref, a.n);
      db.prepare("UPDATE actions SET state = 'uncertain', updated_at = ? WHERE ref = ?").run(at, ref);
    } else if (row.state !== 'uncertain') {
      return { err: [EXIT.human, `${ref} is ${row.state}, not uncertain`] };
    }
    const state = args.sent ? 'reconciled' : 'failed';
    db.prepare('UPDATE actions SET state = ?, remote_id = coalesce(?, remote_id), note = coalesce(?, note), updated_at = ? WHERE ref = ?').run(state, args['remote-id'] ?? null, args.note ?? null, at, ref);
    event(db, ref, args.sent ? 'reconciled-sent' : 'reconciled-failed', { remote_id: args['remote-id'] ?? null, note: args.note ?? null });
    return { state };
  });
  if (out.err) fail(...out.err);
  printKv({ ref, state: out.state });
  return EXIT.ok;
}

function reject(args) {
  only(args, ['_', 'note']);
  const db = openDb();
  const ref = args._[1];
  const out = tx(db, () => {
    const row = getAction(db, ref);
    if (!['proposed', 'approved'].includes(row.state)) return { err: `${ref} is ${row.state}; only proposed or approved actions can be rejected` };
    db.prepare("UPDATE actions SET state = 'rejected', note = coalesce(?, note), updated_at = ? WHERE ref = ?").run(args.note ?? null, isoUtc(Date.now()), ref);
    event(db, ref, 'rejected', args.note ?? null);
    return {};
  });
  if (out.err) fail(EXIT.human, out.err);
  printKv({ ref, state: 'rejected' });
  return EXIT.ok;
}

function expire(args) {
  only(args, ['_', 'now']);
  const db = openDb();
  const ms = nowMs(args);
  const n = tx(db, () => {
    const rows = db.prepare("SELECT * FROM actions WHERE state IN ('proposed', 'approved') AND due_at IS NOT NULL").all().filter((r) => tooLate(r, ms));
    for (const r of rows) {
      db.prepare("UPDATE actions SET state = 'expired', updated_at = ? WHERE ref = ?").run(isoUtc(ms), r.ref);
      event(db, r.ref, 'expired', 'more than 24 hours past its due time');
    }
    return rows.length;
  });
  printKv({ expired: n });
  return EXIT.ok;
}

function doMigrate(args) {
  only(args, ['_']);
  const db = openDb();  // applies anything pending
  migrate(db);
  const rows = db.prepare('SELECT version, name FROM schema_version ORDER BY version').all();
  for (const r of rows) process.stdout.write(`${String(r.version).padStart(3, '0')}-${r.name}\n`);
  printKv({ db: dbPath() });
  return EXIT.ok;
}

export function queue(args) {
  const sub = args._[1];
  const db = openDb();
  if (sub === 'add') {
    only(args, ['_', 'owner', 'kind', 'title', 'due', 'ref', 'note']);
    const owner = checkOwnerId(args.owner);
    if (!readOwner(owner)) fail(EXIT.notFound, `owner not found: ${owner} (no owner.json)`);
    if (!args.kind || !KIND.test(args.kind)) fail(EXIT.usage, 'queue add needs --kind <kebab-case word>');
    if (!args.title || /[\u0000-\u001f]/.test(args.title)) fail(EXIT.usage, 'queue add needs --title <one line>');
    // A whole-day item keeps its calendar date, so it stays on that day if the owner's zone changes.
    let due = null, date = null, allDay = 0;
    if (args.due) { const w = parseWhen(args.due, ownerTz(owner)); if (w.allDay) { date = w.date; allDay = 1; } else due = isoUtc(w.ms); }
    const r = tx(db, () => {
      if (args.ref) {
        const a = getAction(db, args.ref);
        if (a.owner !== owner) fail(EXIT.usage, `${args.ref} belongs to ${a.owner}, not ${owner}`);
      }
      return db.prepare('INSERT INTO queue_items (owner, kind, title, due_at, due_date, all_day, ref, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
        .run(owner, args.kind, args.title, due, date, allDay, args.ref ?? null, args.note ?? null, isoUtc(Date.now()));
    });
    printKv({ id: Number(r.lastInsertRowid) });
    return EXIT.ok;
  }
  if (sub === 'close') {
    only(args, ['_']);
    const id = Number(args._[2]);
    if (!Number.isSafeInteger(id) || id < 1) fail(EXIT.usage, 'queue close <id>');
    const r = tx(db, () => db.prepare("UPDATE queue_items SET state = 'closed', closed_at = ? WHERE id = ? AND state = 'open'").run(isoUtc(Date.now()), id));
    if (r.changes !== 1) {
      if (!db.prepare('SELECT 1 FROM queue_items WHERE id = ?').get(id)) fail(EXIT.notFound, `not found: queue item ${id}`);
      fail(EXIT.human, `queue item ${id} is already closed`);
    }
    printKv({ id, state: 'closed' });
    return EXIT.ok;
  }
  if (sub === 'list') {
    only(args, ['_', 'owner', 'all', 'json']);
    const where = [], params = [];
    if (args.owner) { where.push('owner = ?'); params.push(checkOwnerId(args.owner)); }
    if (!args.all) where.push("state = 'open'");
    const rows = db.prepare(`SELECT * FROM queue_items ${where.length ? `WHERE ${where.join(' AND ')}` : ''} ORDER BY coalesce(due_date, substr(due_at, 1, 10)) IS NULL, coalesce(due_date, substr(due_at, 1, 10)), due_at, id`).all(...params);
    if (args.json) process.stdout.write(`${JSON.stringify(rows)}\n`);
    else for (const r of rows) {
      let when = r.due_date ?? '-';
      if (r.due_at) { const l = localParts(Date.parse(r.due_at), ownerTz(r.owner)); when = `${l.date} ${l.time}`; }
      process.stdout.write(`${r.id}\t${r.state}\t${r.owner}\t${r.kind}\t${when}\t${r.title}\n`);
    }
    return EXIT.ok;
  }
  fail(EXIT.usage, 'queue add|list|close');
}

const COMMANDS = { propose, status, list, claim, record, reconcile, reject, expire, migrate: doMigrate, queue };

async function main(argv) {
  const cmd = argv[0];
  if (!cmd || cmd === '-h' || cmd === '--help' || cmd === 'help') { process.stdout.write(`${USAGE}\n`); return cmd ? EXIT.ok : EXIT.usage; }
  const fn = COMMANDS[cmd];
  if (!fn) fail(EXIT.usage, `unknown command: ${cmd}\n${USAGE}`);
  const args = parseArgs(argv, { multi: ['media'], bool: ['json', 'sent', 'failed', 'all'] });
  return fn(args);
}

if (path.basename(process.argv[1] ?? '') === 'kaito-ledger.mjs') await run(main);
