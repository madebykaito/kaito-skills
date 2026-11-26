// Exercise the scheduler's byte-array handler contract with the real ledger CLIs.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const [repo, ref, prepare] = process.argv.slice(2);
const moduleUrl = (file) => pathToFileURL(repo + '/business/' + file);
const { instagramPublishHandlers } = await import(moduleUrl('handlers/instagram-publish.mjs'));
const { openDb } = await import(moduleUrl('scripts/kaito-ledger-lib.mjs'));
const ledger = (...args) => execFileSync(process.execPath, [repo + '/business/scripts/kaito-ledger.mjs', ...args], { encoding: 'utf8' });
const row = JSON.parse(ledger('status', ref, '--json'));
const handler = instagramPublishHandlers.get(row.action);

if (prepare) {
  assert(handler.prepareAheadMs > 0);
  const result = await handler.prepare(ref, row.digest);
  assert(result.expiresAt > Date.parse(row.due_at));
  assert.match(result.id, /^111:\d+$/);
  assert.equal(JSON.parse(ledger('status', ref, '--json')).state, 'approved');
  if (prepare === 'only') process.exit(0);
  const db = openDb();
  const prepared = db.prepare('SELECT * FROM instagram_prepared_containers ORDER BY container_id').all();
  db.close();
  assert.equal(prepared.length, 2);
  assert.equal(prepared[1].ref, ref);
  assert.equal(prepared[1].digest, row.digest);
  assert.equal(prepared[1].account, row.account);
  assert.equal(prepared[1].container_id, result.id.split(':')[1]);
  assert.notEqual(prepared[0].container_id, prepared[1].container_id);
}
const ready = JSON.parse(ledger('list', '--ready', '--json'));
assert(ready.some((job) => job.ref === ref && job.action === row.action));
const claimed = JSON.parse(ledger('claim', ref, '--digest', row.digest, '--json'));
const out = await handler.publish(ref, row.digest, claimed.attempt);
assert.equal(out.result, 'ok', out.note);
ledger('record', ref, '--attempt', String(claimed.attempt), '--result', out.result, '--remote-id', out.remoteId);
