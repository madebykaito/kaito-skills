// Exercise the scheduler's byte-array handler contract with the real ledger CLIs.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const [repo, ref, prepare] = process.argv.slice(2);
const moduleUrl = (file) => pathToFileURL(repo + '/business/' + file);
const { instagramPublishHandlers } = await import(moduleUrl('handlers/instagram-publish.mjs'));
const { readVerified } = await import(moduleUrl('scripts/kaito-ledger-lib.mjs'));
const ledger = (...args) => execFileSync(process.execPath, [repo + '/business/scripts/kaito-ledger.mjs', ...args], { encoding: 'utf8' });
const row = JSON.parse(ledger('status', ref, '--json'));
const handler = instagramPublishHandlers.get(row.action);
const itemOf = (row) => ({ ...row, text: readVerified(row.text_sha256), media: row.media_sha256.map(readVerified) });
let preparedId;
if (prepare) {
  assert(handler.prepareAheadMs > 0);
  const result = await handler.prepare(itemOf(row), { now: Date.now });
  assert(result.expiresAt > Date.parse(row.due_at));
  assert.match(result.id, /^111:\d+$/);
  assert.equal(JSON.parse(ledger('status', ref, '--json')).state, 'approved');
  if (prepare === 'only') process.exit(0);
  preparedId = result.id;
}
const ready = JSON.parse(ledger('list', '--ready', '--json'));
assert(ready.some((job) => job.ref === ref && job.action === row.action));
const claimed = JSON.parse(ledger('claim', ref, '--digest', row.digest, '--json'));
const out = await handler.publish(itemOf(claimed), { now: Date.now, preparedId });
assert.equal(out.result, 'ok', out.note);
ledger('record', ref, '--attempt', String(claimed.attempt), '--result', out.result, '--remote-id', out.remoteId);
