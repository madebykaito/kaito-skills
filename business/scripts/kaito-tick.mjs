#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import {
  businessDir, checkOwnerId, EXIT, Fail, fail, getAction, isoUtc, nowMs, openDb, readVerified, run, tx, verifyAction,
} from './kaito-ledger-lib.mjs';
import { claimAction, recordResult } from './kaito-ledger.mjs';
import { dailyHandlers, handlers } from '../handlers/registry.mjs';
import { prepare, publish, STALE_MS } from '../handlers/contract.mjs';
import { delegate, syncDelegated } from './kaito-worker-sync.mjs';

function readItem(row) {
  return {
    ref: row.ref, digest: row.digest, idempotency_key: row.op_key,
    owner: row.owner, account: row.account, action: row.action, disclosure: row.disclosure,
    due_at: row.due_at, text: row.text_sha256 ? readVerified(row.text_sha256) : null,
    media: JSON.parse(row.media_json).map(readVerified),
  };
}

function record(db, ref, result, remoteId, note) {
  try {
    const state = recordResult(db, ref, 1, result, remoteId, note);
    console.log(`${state}=${ref}`);
  } catch (error) {
    if (!(error instanceof Fail) || error.code !== EXIT.human) throw error;
  }
}

async function prepareEarly(db, row, handler, now) {
  const token = randomUUID();
  const reserved = tx(db, () => {
    if (getAction(db, row.ref).state !== 'approved') return false;
    if (!db.prepare('SELECT 1 FROM approvals WHERE ref = ? AND digest = ?').get(row.ref, row.digest)) return false;
    const ms = now();
    const due = Date.parse(row.due_at);
    if (due <= ms || due > ms + handler.prepareAheadMs) return false;
    const previous = db.prepare('SELECT * FROM scheduler_preparations WHERE ref = ?').get(row.ref);
    if (previous && (previous.expires_at > due || previous.started_at > ms - STALE_MS)) return false;
    if (verifyAction(row).problems.length) fail(EXIT.human, 'approved payload changed');
    db.prepare(`INSERT INTO scheduler_preparations (ref, token, started_at) VALUES (?, ?, ?)
      ON CONFLICT(ref) DO UPDATE SET token = excluded.token, started_at = excluded.started_at,
      remote_id = NULL, expires_at = NULL`).run(row.ref, token, ms);
    return true;
  });
  if (!reserved) return;
  const { id, expiresAt } = await prepare(handler, readItem(row), { now });
  db.prepare('UPDATE scheduler_preparations SET remote_id = ?, expires_at = ? WHERE ref = ? AND token = ?')
    .run(id, expiresAt, row.ref, token);
  console.log(`prepared=${row.ref}`);
}

async function send(db, row, handler, now) {
  const claim = claimAction(db, row.ref, row.digest, {
    clock: now,
    onClaim: () => db.prepare('INSERT INTO scheduler_claims (ref) VALUES (?)').run(row.ref),
  });
  let item;
  try { item = readItem(row); } catch {
    record(db, row.ref, 'failed', null, 'artifact could not be verified before send');
    return;
  }
  const preparedId = db.prepare('SELECT remote_id FROM scheduler_preparations WHERE ref = ? AND expires_at > ?')
    .get(row.ref, now())?.remote_id ?? null;
  const out = await publish(handler, { ...item, attempt: claim.attempt }, { now, preparedId, allowCloud: true });
  record(db, row.ref, out.result, out.remoteId, out.note);
}

async function pullInsights() {
  let owners;
  try {
    owners = JSON.parse(fs.readFileSync(path.join(businessDir(), 'instagram-insights.json'), 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    console.error('invalid business/instagram-insights.json');
    return true;
  }
  if (!Array.isArray(owners)) {
    console.error('business/instagram-insights.json must be an array of owner IDs');
    return true;
  }
  let errors = false;
  for (const owner of new Set(owners)) {
    try {
      if (typeof owner !== 'string') fail(EXIT.usage, 'insights owner ID must be a string');
      const out = await dailyHandlers.get('instagram-insights').run({ owner: checkOwnerId(owner) }, { now: Date.now });
      if (out.status === 'pulled') console.log(`instagram-insights=${owner} ${out.date} metrics=${out.metrics}`);
    } catch {
      console.error('daily Instagram insights pull failed');
      errors = true;
    }
  }
  return errors;
}

await run(async (args) => {
  const usage = 'usage: kaito-tick.mjs [sync <approved-ref>]';
  if (args.length === 1 && args[0] === '--help') { console.log(usage); return; }
  if (args.length && (args.length !== 2 || args[0] !== 'sync')) fail(EXIT.usage, usage);
  const db = openDb();
  try {
    if (args.length) {
      await delegate(db, getAction(db, args[1]), readItem);
      return (await syncDelegated(db, readItem, record, args[1])) ? EXIT.error : EXIT.ok;
    }
    const fake = process.env.KAITO_TEST_NOW;
    const clock = (verb) => fake && verb === 'noop-test' ? () => nowMs({ now: fake }) : Date.now;
    const localClaims = db.prepare(`SELECT a.ref, a.action, t.claimed_at FROM scheduler_claims s
      JOIN actions a USING (ref) JOIN attempts t USING (ref) WHERE s.worker_url IS NULL AND a.state = 'claimed'`).all();
    for (const row of localClaims) {
      if (Date.parse(row.claimed_at) <= clock(row.action)() - STALE_MS) {
        record(db, row.ref, 'uncertain', null, 'scheduler stopped before recording the result');
      }
    }

    let errors = false;
    const rows = db.prepare(`SELECT * FROM actions WHERE state = 'approved'
      AND due_at IS NOT NULL ORDER BY due_at, ref`).all();
    for (const row of rows) {
      const handler = handlers.get(row.action);
      if (!handler) continue;
      const now = clock(row.action);
      try {
        if (row.due_at <= isoUtc(now())) await send(db, row, handler, now);
        else if (handler.prepare) await prepareEarly(db, row, handler, now);
      } catch (error) {
        const current = getAction(db, row.ref).state;
        if (error instanceof Fail && error.code === EXIT.human && current !== 'approved') continue;
        console.error(`${row.ref}: scheduler could not process this action${error instanceof Fail ? `: ${error.message}` : ''}`);
        errors = true;
      }
    }
    if (await syncDelegated(db, readItem, record)) errors = true;
    if (await pullInsights()) errors = true;
    return errors ? EXIT.error : EXIT.ok;
  } finally { db.close(); }
});
