import fs from 'node:fs';
import path from 'node:path';
import { businessDir, EXIT, fail, isoUtc, readOwner } from './kaito-ledger-lib.mjs';
import { claimAction } from './kaito-ledger.mjs';
import { cloudHandlers } from '../handlers/cloud-registry.mjs';
import { validId } from '../handlers/contract.mjs';
import { hmacKey, LATE_MS, MAX_BODY, sign } from '../worker/protocol.mjs';

function config() {
  let cfg, url;
  try {
    cfg = JSON.parse(fs.readFileSync(path.join(businessDir(), 'worker.json'), 'utf8'));
    url = new URL(cfg.url);
    const loopback = url.protocol === 'http:' && url.hostname === '127.0.0.1';
    if ((!loopback && url.protocol !== 'https:') || url.username || url.password ||
        url.search || url.hash || url.pathname !== '/queue' || !path.isAbsolute(cfg.key_file) ||
        !Array.isArray(cfg.owners)) throw new Error();
  } catch { fail(EXIT.usage, 'worker.json needs a /queue HTTPS URL, absolute key_file and owners array'); }
  return { ...cfg, url: url.href };
}

function requireConsent(cfg, row) {
  if (!cfg.owners.includes(row.owner) || readOwner(row.owner)?.cloud_ok !== true) {
    fail(EXIT.human, 'Worker transfer requires owner cloud consent');
  }
}

function packet(row, readItem) {
  const item = readItem(row);
  return JSON.stringify({
    op: 'enqueue',
    item: { ...item, attempt: 1, text: item.text?.toString('base64') ?? null, media: item.media.map((bytes) => bytes.toString('base64')) },
  });
}

export async function delegate(db, row, readItem) {
  const routed = db.prepare('SELECT worker_url FROM scheduler_claims WHERE ref = ?').get(row.ref);
  if (routed?.worker_url) return;
  if (row.state !== 'approved' || !row.due_at || !cloudHandlers.get(row.action)?.cloud) {
    fail(EXIT.human, 'Worker handoff needs an approved, scheduled ref with a cloud handler');
  }
  const cfg = config();
  requireConsent(cfg, row);
  await workerKey(cfg);
  if (Buffer.byteLength(packet(row, readItem)) > MAX_BODY) fail(EXIT.human, 'approved payload exceeds the Worker queue limit');
  claimAction(db, row.ref, row.digest, {
    delegate: true,
    onClaim: () => db.prepare('INSERT INTO scheduler_claims (ref, worker_url, worker_until) VALUES (?, ?, ?)')
      .run(row.ref, cfg.url, isoUtc(Date.parse(row.due_at) + LATE_MS)),
  });
}

async function workerKey(cfg) {
  try { return await hmacKey(fs.readFileSync(cfg.key_file, 'utf8').trim()); }
  catch { fail(EXIT.usage, 'cannot read the Worker HMAC key'); }
}

async function request(cfg, key, body) {
  if (Buffer.byteLength(body) > MAX_BODY) throw new Error('queue limit exceeded');
  const response = await fetch(cfg.url, {
    method: 'POST', body, redirect: 'error', signal: AbortSignal.timeout(10_000),
    headers: { 'content-type': 'application/json', 'x-kaito-signature': await sign(key, body) },
  });
  if (!response.ok) throw new Error('Worker request failed');
  return response.json();
}

export async function syncDelegated(db, readItem, record, ref = null) {
  const rows = db.prepare(`SELECT a.*, s.worker_url, s.worker_until, s.worker_accepted FROM scheduler_claims s
    JOIN actions a USING (ref) JOIN attempts t USING (ref)
    WHERE s.worker_url IS NOT NULL AND s.worker_done = 0 AND (a.state = 'claimed' OR (a.state = 'failed' AND t.result = 'uncertain'))
    AND (? IS NULL OR a.ref = ?)`).all(ref, ref);
  if (!rows.length) return false;
  const cfg = config();
  const key = await workerKey(cfg);
  let errors = false;
  for (const row of rows) {
    try {
      if (row.worker_url !== cfg.url) throw new Error('Worker URL changed');
      let response = await request(cfg, key, JSON.stringify({ op: 'status', ref: row.ref, digest: row.digest }));
      if (response.state === 'missing' && row.state === 'claimed') {
        if (Date.now() > Date.parse(row.worker_until)) {
          record(db, row.ref, 'uncertain', null, 'Worker execution window closed without a queue entry');
          continue;
        }
        if (row.worker_accepted) throw new Error('acknowledged Worker queue entry disappeared');
        requireConsent(cfg, row);
        if (db.prepare('SELECT state FROM actions WHERE ref = ?').get(row.ref).state !== 'claimed') continue;
        response = await request(cfg, key, packet(row, readItem));
      }
      if (response.state === 'queued' || response.state === 'claimed') {
        db.prepare('UPDATE scheduler_claims SET worker_accepted = 1 WHERE ref = ?').run(row.ref);
        if (ref) console.log(`delegated=${row.ref}`);
      } else if (['ok', 'failed', 'uncertain'].includes(response.state)
        && (response.remoteId == null || validId(response.remoteId))) {
        if (row.state === 'claimed' || response.state === 'ok') record(db, row.ref, response.state, response.remoteId ?? null);
        db.prepare('UPDATE scheduler_claims SET worker_accepted = 1, worker_done = 1 WHERE ref = ?').run(row.ref);
      } else if (response.state !== 'missing') {
        throw new Error('unexpected Worker result');
      }
    } catch {
      console.error(`${row.ref}: Worker sync failed`);
      errors = true;
    }
  }
  return errors;
}
