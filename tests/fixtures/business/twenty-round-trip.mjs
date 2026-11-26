import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { randomUUID } from 'node:crypto';

const [repo, home] = process.argv.slice(2);
const run = promisify(execFile);
const owner = 'lumen-tea';
const root = path.join(process.env.KAITO_HOME, 'owners', owner);
await fs.mkdir(root, { recursive: true });
const key = 'test-twenty-key';
await fs.writeFile(path.join(home, 'crm.key'), key);
await fs.writeFile(path.join(root, 'owner.json'), JSON.stringify({
  id: owner, name: 'Lumen Tea Co.', kind: 'company', keys: { twenty: path.join(home, 'crm.key') },
}));
const remote = new Map();
let writes = 0;
let dropPatch = false;
let reassignBeforePatch = false;
const inbound = {
  id: randomUUID(), kaitoOwner: owner, name: 'Remote Lead', email: 'remote@example.test',
  company: 'Tea Shop', stage: 'review', updatedAt: '2024-01-01T00:00:00.000Z',
};
remote.set(inbound.id, inbound);
const unrelated = { ...inbound, id: randomUUID(), kaitoOwner: 'ira-das', email: 'unrelated@example.test' };
remote.set(unrelated.id, unrelated);
const server = http.createServer(async (req, res) => {
  try {
    assert.equal(req.headers.authorization, `Bearer ${key}`);
    const url = new URL(req.url, 'http://localhost');
    const [, rest, object, id] = url.pathname.split('/');
    assert.equal(rest, 'rest');
    assert.equal(object, 'kaitoLeads');
    res.setHeader('content-type', 'application/json');
    if (req.method === 'GET' && !id) {
      const records = [...remote.values()];
      const offset = Number(url.searchParams.get('starting_after') ?? 0);
      return res.end(JSON.stringify({ data: { kaitoLeads: records.slice(offset, offset + 1) },
        pageInfo: { hasNextPage: offset + 1 < records.length, endCursor: String(offset + 1) } }));
    }
    let body = '';
    for await (const chunk of req) body += chunk;
    const payload = JSON.parse(body);
    if (req.method === 'POST') {
      assert.match(payload.id, /^[\da-f]{8}-[\da-f]{4}-5[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/);
      if (remote.has(payload.id)) return res.writeHead(409).end('{}');
      const record = { ...payload, updatedAt: new Date().toISOString() };
      writes++;
      remote.set(record.id, record);
      return res.end(JSON.stringify({ data: { createKaitoLead: record } }));
    }
    assert.equal(req.method, 'PATCH');
    assert.equal(id, undefined);
    const filter = url.searchParams.get('filter');
    const match = /^id\[eq\]:([a-f0-9-]+),kaitoOwner\[eq\]:([a-z-]+),updatedAt\[eq\]:'([^']+)'$/.exec(filter);
    assert(match);
    const [, recordId, scope, updatedAt] = match;
    const current = remote.get(recordId);
    if (reassignBeforePatch) current.kaitoOwner = 'ira-das';
    if (current?.kaitoOwner !== scope || current.updatedAt !== updatedAt) {
      return res.end(JSON.stringify({ data: { updateKaitoLeads: [] } }));
    }
    const record = { ...current, ...payload, updatedAt: new Date().toISOString() };
    writes++;
    remote.set(recordId, record);
    if (dropPatch) return req.socket.destroy();
    res.end(JSON.stringify({ data: { updateKaitoLeads: [record] } }));
  } catch {
    res.writeHead(400);
    res.end('{}');
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const env = { ...process.env, TWENTY_URL: `http://127.0.0.1:${server.address().port}` };
const cli = async (script, ...args) => (await run(process.execPath,
  [path.join(repo, 'business/scripts', `kaito-${script}.mjs`), ...args, '--owner', owner], { env })).stdout;
const sync = (...args) => cli('twenty', 'sync', ...args);
const list = async () => JSON.parse(await cli('leads', 'list', '--json'));
try {
  const db = path.join(env.KAITO_HOME, 'business/ledger.db');
  assert.match(await sync(), /pull=1/);
  await assert.rejects(fs.stat(db), { code: 'ENOENT' });
  assert.equal(writes, 0);
  const csv = path.join(home, 'leads.csv');
  await fs.writeFile(csv, 'name,email,company\nLocal Lead,local@example.test,Tea Room\n');
  await cli('leads', 'import', csv);
  const before = await fs.readFile(db);
  const ledgerFiles = await fs.readdir(path.dirname(db));
  assert.match(await sync(), /push=1/);
  assert.deepEqual(await fs.readFile(db), before);
  assert.deepEqual(await fs.readdir(path.dirname(db)), ledgerFiles);
  assert.equal(writes, 0);

  await sync('--apply');
  assert.equal(writes, 1);
  const local = (await list()).find(row => row.email === 'local@example.test');
  assert.equal((await list()).find(row => row.email === inbound.email).stage, 'review');
  assert.equal((await list()).length, 2);
  let mirrored = [...remote.values()].find(row => row.email === local.email);
  assert.equal(mirrored.company, 'Tea Room');
  await sync('--apply');
  assert.equal(writes, 1);

  // Distinct edits on the two sides must both survive, even with a newer remote record.
  await cli('leads', 'move', String(local.id), '--stage', 'outreach', '--note', 'Contact planned');
  remote.set(mirrored.id, { ...mirrored, company: 'New Tea Room', updatedAt: '2099-01-01T00:00:00.000Z' });
  assert.match(await sync('--apply'), /conflicts=0/);
  assert.equal(remote.get(mirrored.id).stage, 'outreach');
  assert.equal((await list()).find(row => row.id === local.id).company, 'New Tea Room');

  // Both changed stage. The remote timestamp wins and the losing value is logged.
  mirrored = remote.get(mirrored.id);
  await cli('leads', 'move', String(local.id), '--stage', 'review', '--note', 'Reviewed');
  remote.set(mirrored.id, { ...mirrored, stage: 'retro', updatedAt: '2099-01-02T00:00:00.000Z' });
  assert.match(await sync(), /conflicts=1/);
  assert.equal((await list()).find(row => row.id === local.id).stage, 'review');
  assert.match(await sync('--apply'), /conflicts=1/);
  assert.equal((await list()).find(row => row.id === local.id).stage, 'retro');
  const conflict = await run(process.execPath, ['--no-warnings', '-e', `
    const { DatabaseSync } = require('node:sqlite');
    const db = new DatabaseSync(process.argv[1], { readOnly: true });
    console.log(JSON.stringify(db.prepare('SELECT field, local_value, remote_value, winner FROM twenty_conflicts').all()));
  `, db]);
  assert.deepEqual(JSON.parse(conflict.stdout), [{ field: 'stage', local_value: 'review', remote_value: 'retro', winner: 'remote' }]);
  assert.match(await sync('--apply'), /conflicts=0/);

  // A lost response must still leave one audit row for the local-winner conflict.
  await cli('leads', 'move', String(local.id), '--stage', 'outreach', '--note', 'Reopened');
  mirrored = remote.get(mirrored.id);
  remote.set(mirrored.id, { ...mirrored, stage: 'qualify', updatedAt: '2024-02-01T00:00:00.000Z' });
  dropPatch = true;
  await assert.rejects(sync('--apply'));
  dropPatch = false;
  assert.equal(remote.get(mirrored.id).stage, 'outreach');
  assert.match(await sync('--apply'), /conflicts=0/);
  const audit = await run(process.execPath, ['--no-warnings', '-e', `
    const db = new (require('node:sqlite').DatabaseSync)(process.argv[1]);
    console.log(db.prepare("SELECT count(*) AS n FROM twenty_conflicts WHERE winner='local'").get().n);
  `, db]);
  assert.equal(audit.stdout.trim(), '1');

  // Free an address on the pulled lead before assigning it to the earlier local ID.
  const other = remote.get(inbound.id);
  remote.set(inbound.id, { ...other, email: 'changed@example.com', updatedAt: '2099-01-03T00:00:00.000Z' });
  remote.set(mirrored.id, { ...remote.get(mirrored.id), email: other.email, updatedAt: '2099-01-03T00:00:00.000Z' });
  assert.match(await sync('--apply'), /pull=2/);
  assert.equal((await list()).find(row => row.id === local.id).email, other.email);

  await cli('leads', 'move', String(local.id), '--stage', 'review', '--note', 'Reviewed again');
  reassignBeforePatch = true;
  await assert.rejects(sync('--apply'), error => error.code === 3);
  assert.equal(remote.get(mirrored.id).stage, 'outreach');
} finally {
  server.close();
}
