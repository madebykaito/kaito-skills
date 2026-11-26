#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  EXIT, checkOwnerId, dbPath, fail, isoUtc, only, openDb, parseArgs, printKv, readOwner, run, tx,
} from './kaito-ledger-lib.mjs';
const { DatabaseSync } = await import('node:sqlite');

const fields = ['name', 'email', 'company', 'stage'];
const stages = ['qualify', 'outreach', 'review', 'retro'];
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const uuid = /^[\da-f]{8}-[\da-f]{4}-[1-5][\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/i;
const leadNamespace = Buffer.from('cc8378c256b94842af23cb044dd8746c', 'hex');
const values = row => Object.fromEntries(fields.map(field => [field, row[field]]));

function remoteRecord(row, owner) {
  if (row?.kaitoOwner !== owner || !uuid.test(row.id) || !Number.isFinite(Date.parse(row.updatedAt)) ||
      typeof row.name !== 'string' || !row.name.trim() || typeof row.email !== 'string' ||
      !emailPattern.test(row.email.trim()) || !stages.includes(row.stage) ||
      (row.company != null && typeof row.company !== 'string') ||
      /[\r\n\t]/.test(row.name + (row.company ?? ''))) {
    fail(EXIT.error, 'Twenty returned an invalid lead. Check the Kaito Lead object fields.');
  }
  return { ...row, email: row.email.trim().toLowerCase(), company: row.company ?? '' };
}

function twentyApi(owner) {
  let url;
  try { url = new URL(process.env.TWENTY_URL ?? 'http://127.0.0.1:3319'); } catch { /* invalid */ }
  const loopback = ['127.0.0.1', '[::1]', 'localhost'].includes(url?.hostname);
  if (!url || !(url.protocol === 'https:' || (loopback && url.protocol === 'http:')) ||
      url.username || url.password || url.search || url.hash) fail(EXIT.usage, 'TWENTY_URL needs HTTPS or loopback HTTP');
  if (!loopback && !owner.cloud_ok) fail(EXIT.human, 'remote Twenty sync requires owner cloud consent');
  let key;
  try {
    const file = owner.keys.twenty;
    key = fs.readFileSync(file.startsWith('~/') ? path.join(os.homedir(), file.slice(2)) : file, 'utf8').trim();
    if (!/^[!-~]+$/.test(key)) throw new Error();
  } catch { fail(EXIT.error, 'cannot read the API token from the owner’s keys.twenty file'); }
  const resource = url.href.replace(/\/$/, '') + '/rest/kaitoLeads';
  return async (route, method = 'GET', body) => {
    let response;
    try {
      response = await fetch(resource + route, { method, headers: {
        Authorization: `Bearer ${key}`, 'Content-Type': 'application/json',
      }, body: JSON.stringify(body), redirect: 'error', signal: AbortSignal.timeout(8000) });
    } catch { fail(EXIT.error, 'Twenty request failed'); }
    if (!response.ok) fail(EXIT.error, `Twenty returned HTTP ${response.status}`);
    try { return await response.json(); } catch { fail(EXIT.error, 'Twenty returned invalid JSON'); }
  };
}

async function getRemote(api, owner) {
  const records = new Map();
  const cursors = new Set();
  const query = new URLSearchParams({ limit: '100', filter: `kaitoOwner[eq]:${owner}` });
  for (;;) {
    const { data, pageInfo } = await api(`?${query}`);
    if (!Array.isArray(data?.kaitoLeads) || typeof pageInfo?.hasNextPage !== 'boolean') {
      fail(EXIT.error, 'Twenty returned an invalid lead list');
    }
    for (const row of data.kaitoLeads) {
      if (row?.kaitoOwner !== owner) continue;
      const lead = remoteRecord(row, owner);
      if (records.has(lead.id)) fail(EXIT.error, 'Twenty returned a duplicate lead ID');
      records.set(lead.id, lead);
    }
    if (!pageInfo.hasNextPage) return records;
    const next = pageInfo.endCursor;
    if (!next || cursors.has(next)) fail(EXIT.error, 'Twenty pagination did not advance');
    cursors.add(next);
    query.set('starting_after', next);
  }
}

function table(db, name) {
  return db?.prepare("SELECT 1 FROM sqlite_schema WHERE type='table' AND name=?").get(name);
}

function localSnapshot(db, owner) {
  if (!table(db, 'leads')) return [];
  const hasShadow = table(db, 'twenty_shadow');
  const local = db.prepare(hasShadow
    ? 'SELECT l.*, t.remote_id FROM leads l LEFT JOIN twenty_leads t ON t.lead_id=l.id WHERE l.owner=? ORDER BY l.id'
    : 'SELECT l.*, coalesce((SELECT max(at) FROM lead_stages WHERE lead_id=l.id), created_at) AS updated_at FROM leads l WHERE l.owner=? ORDER BY l.id'
  ).all(owner);
  if (hasShadow) {
    const shadow = db.prepare('SELECT field,value,local_at,remote_at FROM twenty_shadow WHERE lead_id=? ORDER BY field');
    for (const lead of local) lead.shadow = Object.fromEntries(shadow.all(lead.id).map(row => [row.field, row]));
  }
  return local;
}

function drySnapshot(file, owner) {
  const sources = [file, file + '-wal'];
  const identity = source => {
    const s = fs.statSync(source, { bigint: true, throwIfNoEntry: false });
    return s ? `${s.ino}:${s.size}:${s.mtimeNs}:${s.ctimeNs}` : null;
  };
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'kaito-twenty-'));
  try {
    for (let attempt = 0; attempt < 3; attempt++) {
      const before = sources.map(identity);
      if (!before[0]) return [];
      const copy = path.join(tmp, 'ledger.db');
      fs.rmSync(copy + '-wal', { force: true });
      try {
        sources.forEach((source, index) => {
          if (before[index]) fs.copyFileSync(source, copy + (index ? '-wal' : ''), fs.constants.COPYFILE_FICLONE);
        });
      } catch (error) {
        if (error.code === 'ENOENT') continue;
        throw error;
      }
      if (sources.some((source, index) => identity(source) !== before[index])) continue;
      // SQLite may create WAL sidecars even for a read-only connection. Open only the copy.
      const db = new DatabaseSync(copy, { readOnly: true });
      try { return localSnapshot(db, owner); } finally { db.close(); }
    }
    fail(EXIT.human, 'the ledger changed while taking the dry-run snapshot; run sync again');
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
}

function pairLeads(local, remote) {
  const byEmail = new Map();
  const used = new Set(local.map(row => row.remote_id).filter(Boolean));
  for (const row of remote.values()) {
    if (byEmail.has(row.email)) fail(EXIT.human, 'multiple Twenty leads share an email for this owner');
    byEmail.set(row.email, row);
  }
  const pairs = [];
  for (const row of local) {
    const candidate = byEmail.get(row.email);
    const other = row.remote_id ? remote.get(row.remote_id) : candidate && !used.has(candidate.id) ? candidate : undefined;
    if (other) used.add(other.id);
    pairs.push([row, other]);
  }
  for (const row of remote.values()) if (!used.has(row.id)) pairs.push([null, row]);
  return pairs;
}

function plan(local, remote) {
  const patch = {}, pull = {}, conflicts = [];
  if (!local || !remote) return { patch, pull, conflicts };
  for (const field of fields) {
    const left = local[field], right = remote[field];
    if (left === right) continue;
    const prior = local.shadow?.[field]?.value;
    const localChanged = left !== prior;
    const remoteChanged = right !== prior;
    const localWins = !remoteChanged || (localChanged && Date.parse(local.updated_at) >= Date.parse(remote.updatedAt));
    if (localWins) patch[field] = left;
    else pull[field] = right;
    if (localChanged && remoteChanged) conflicts.push({ field, prior, left, right, winner: localWins ? 'local' : 'remote' });
  }
  return { patch, pull, conflicts };
}

function remoteId(owner, row) {
  // A repeat after a lost response must target the same create identity.
  const bytes = createHash('sha1').update(leadNamespace).update(`${owner}\0${row.email}`).digest();
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.subarray(0, 16).toString('hex');
  return hex.replace(/^(........)(....)(....)(....)(............)$/, '$1-$2-$3-$4-$5');
}

function checkLocal(db, owner, local) {
  if (!local) return;
  const current = db.prepare('SELECT * FROM leads WHERE owner=? AND id=?').get(owner, local.id);
  if (!current || current.updated_at !== local.updated_at || fields.some(f => current[f] !== local[f])) {
    fail(EXIT.human, 'a local lead changed during sync; run sync again');
  }
  if (db.prepare('SELECT remote_id FROM twenty_leads WHERE lead_id=?').get(local.id)?.remote_id !== (local.remote_id ?? undefined)) {
    fail(EXIT.human, 'a lead association changed during sync; run sync again');
  }
}

function logConflicts(db, local, remote, conflicts, now) {
  if (!conflicts.length) return;
  const log = db.prepare(`INSERT INTO twenty_conflicts
    (lead_id,field,previous_value,local_value,remote_value,local_at,remote_at,winner,observed_at)
    VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(lead_id,field,local_at,remote_at,local_value,remote_value) DO NOTHING`);
  for (const row of conflicts) log.run(local.id, row.field, row.prior ?? null, row.left, row.right,
    local.updated_at, remote.updatedAt, row.winner, now);
}

async function applyPair(db, api, owner, local, remote, { patch, pull, conflicts }) {
  const now = isoUtc(Date.now());
  if (!remote) {
    checkLocal(db, owner, local);
    const created = await api('', 'POST', { id: remoteId(owner, local), kaitoOwner: owner, ...values(local) });
    remote = remoteRecord(created.data?.createKaitoLead, owner);
  } else if (Object.keys(patch).length) {
    tx(db, () => {
      checkLocal(db, owner, local);
      // Keep the observed conflict even if Twenty commits the PATCH and drops its response.
      logConflicts(db, local, remote, conflicts, now);
    });
    const stamp = new Date(remote.updatedAt).toISOString();
    const filter = new URLSearchParams({ filter: `id[eq]:${remote.id},kaitoOwner[eq]:${owner},updatedAt[eq]:'${stamp}'` });
    const updated = (await api(`?${filter}`, 'PATCH', patch)).data?.updateKaitoLeads;
    if (!Array.isArray(updated)) fail(EXIT.error, 'Twenty returned an invalid update result');
    if (!updated.length) fail(EXIT.human, 'the Twenty lead changed during sync; run sync again');
    if (updated.length !== 1 || updated[0]?.id !== remote.id) fail(EXIT.error, 'Twenty returned a different lead ID');
    remote = remoteRecord(updated[0], owner);
  }
  tx(db, () => {
    checkLocal(db, owner, local);
    let leadId = local?.id;
    let localAt = local?.updated_at;
    if (!local) {
      leadId = db.prepare('INSERT INTO leads(owner,name,email,company,stage,created_at) VALUES (?,?,?,?,?,?)')
        .run(owner, ...fields.map(f => remote[f]), now).lastInsertRowid;
      localAt = now;
    } else {
      const expected = { ...values(local), ...pull };
      if (fields.some(f => remote[f] !== expected[f])) fail(EXIT.error, 'Twenty did not retain the synchronized values');
      if (Object.keys(pull).length) {
        db.prepare('UPDATE leads SET name=?,email=?,company=?,stage=? WHERE id=?')
          .run(...fields.map(f => expected[f]), leadId);
        localAt = db.prepare('SELECT updated_at FROM leads WHERE id=?').get(leadId).updated_at;
      }
    }
    if (!local || Object.hasOwn(pull, 'stage')) {
      db.prepare("INSERT INTO lead_stages(lead_id,stage,note,at) VALUES (?,?,'Synced from Twenty',?)")
        .run(leadId, remote.stage, now);
    }
    db.prepare('INSERT INTO twenty_leads VALUES (?,?) ON CONFLICT(lead_id) DO NOTHING').run(leadId, remote.id);
    if (!Object.keys(patch).length) logConflicts(db, local, remote, conflicts, now);
    const shadow = db.prepare(`INSERT INTO twenty_shadow VALUES (?,?,?,?,?) ON CONFLICT(lead_id,field)
      DO UPDATE SET value=excluded.value,local_at=excluded.local_at,remote_at=excluded.remote_at`);
    for (const field of fields) {
      if (local?.shadow?.[field]?.value !== remote[field]) shadow.run(leadId, field, remote[field], localAt, remote.updatedAt);
    }
  });
}

function planPairs(local, remote) {
  const occupied = new Set(local.map(row => row.email));
  const finalEmails = new Set();
  const waiting = new Map();
  const ordered = [];
  for (const [row, other] of pairLeads(local, remote)) {
    const change = plan(row, other);
    const email = change.pull.email ?? row?.email ?? other.email;
    if (finalEmails.has(email)) fail(EXIT.human, 'the sync would give two local leads the same email');
    finalEmails.add(email);
    const item = { local: row, other, change, email };
    if (email !== row?.email && occupied.has(email)) waiting.set(email, item);
    else ordered.push(item);
  }
  for (const { local: row, email } of ordered) {
    if (row && row.email !== email && waiting.has(row.email)) {
      ordered.push(waiting.get(row.email));
      waiting.delete(row.email);
    }
  }
  if (waiting.size) fail(EXIT.human, 'lead emails form a cycle; free one address in Twenty before syncing');
  return ordered;
}

await run(async argv => {
  const args = parseArgs(argv, { bool: ['apply'] });
  only(args, ['owner', 'apply']);
  if (args._.length !== 1 || args._[0] !== 'sync' || !args.owner) fail(EXIT.usage, 'usage: kaito-twenty.mjs sync --owner <id> [--apply]');
  const owner = checkOwnerId(args.owner);
  const resolver = spawnSync(process.execPath, [path.join(import.meta.dirname, 'kaito-owner.mjs'), 'resolve', '--owner', owner],
    { encoding: 'utf8', stdio: ['ignore', 'ignore', 'pipe'] });
  if (resolver.status !== 0) fail(resolver.status || EXIT.error, 'cannot resolve the Twenty sync owner');
  const record = readOwner(owner);
  if (!record || record.id !== owner) fail(EXIT.notFound, 'owner not found');
  const api = twentyApi(record);
  const remote = await getRemote(api, owner);
  const db = args.apply ? openDb() : null;
  const totals = { mode: args.apply ? 'apply' : 'dry-run', push: 0, pull: 0, conflicts: 0, missing: 0 };
  try {
    const localRows = db ? localSnapshot(db, owner) : drySnapshot(dbPath(), owner);
    for (const { local, other, change } of planPairs(localRows, remote)) {
      if (!other && local.remote_id) { totals.missing++; continue; }
      const push = !other || Object.keys(change.patch).length > 0;
      const pull = !local || Object.keys(change.pull).length > 0;
      totals.push += Number(push);
      totals.pull += Number(pull);
      totals.conflicts += change.conflicts.length;
      if (args.apply && (push || pull || local?.remote_id !== other.id || fields.some(f => local.shadow?.[f]?.value !== other[f]))) {
        await applyPair(db, api, owner, local, other, change);
      }
    }
  } finally { db?.close(); }
  printKv(totals);
});
