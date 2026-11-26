// Seed consent only in an ephemeral fictional ledger. This fixture never invokes approval.
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';

const [repo, ref, digest] = process.argv.slice(2);
const root = fs.realpathSync(process.env.KAITO_HOME);
assert.ok([fs.realpathSync(os.tmpdir()), fs.realpathSync('/tmp')].some((tmp) => root.startsWith(tmp + path.sep)));
assert.equal(path.basename(process.env.KAITO_HOME), '.kaito');
const { openDb, getAction, isoUtc, tx } = await import(pathToFileURL(path.join(repo, 'business/scripts/kaito-ledger-lib.mjs')));
const db = openDb();
tx(db, () => {
  const row = getAction(db, ref);
  assert.equal(row.owner, 'lumen-tea');
  assert.equal(row.action, 'noop-test');
  assert.equal(row.state, 'proposed');
  assert.equal(row.digest, digest);
  const at = isoUtc(Date.now());
  db.prepare("INSERT INTO approvals (ref, digest, via, at) VALUES (?, ?, 'terminal', ?)").run(ref, digest, at);
  db.prepare("UPDATE actions SET state = 'approved', approved_at = ?, approved_via = 'terminal' WHERE ref = ?").run(at, ref);
});
