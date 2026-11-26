import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createServer } from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const repo = process.argv[2];
const load = (file) => import(pathToFileURL(path.join(repo, 'business', file)));
const { accept, tick } = await load('worker/index.mjs');
const { hmacKey, sign, LATE_MS } = await load('worker/protocol.mjs');
const { STALE_MS } = await load('handlers/contract.mjs');
const { d1Queue } = await load('worker/d1-queue.mjs');
const { openDb } = await load('scripts/kaito-ledger-lib.mjs');
const { DatabaseSync } = await import('node:sqlite');
const secret = randomBytes(32).toString('hex');
const key = await hmacKey(secret);

function fakeKV() {
  const kv = new Map();
  const queued = () => [...kv.values()].filter((job) => job.state === 'queued').map((job) => ({ ...job }));
  return {
    kv,
    async enqueue(job) {
      if (!kv.has(job.ref)) kv.set(job.ref, { ...job, state: 'queued' });
    },
    async status(ref) { return kv.get(ref); },
    async due(now) { return queued().filter((job) => job.due_at <= now); },
    async upcoming(now, lead) { return queued().filter((job) => job.due_at > now && job.due_at <= now + lead); },
    async reservePreparation(ref, now) {
      const job = kv.get(ref);
      if (job.state !== 'queued' || job.prepared_at != null) return false;
      job.prepared_at = now;
      return true;
    },
    async prepared(ref, now, id, until) {
      Object.assign(kv.get(ref), { prepared_id: id, prepared_until: until });
    },
    async claim(ref, now) {
      const job = kv.get(ref);
      if (job.state !== 'queued' || job.due_at > now || job.due_at < now - LATE_MS) return null;
      Object.assign(job, { state: 'claimed', claimed_at: now });
      return { ...job };
    },
    async finish(ref, { result, remoteId }) {
      Object.assign(kv.get(ref), { state: result, remote_id: remoteId });
    },
    async sweep(now) {
      for (const job of kv.values()) {
        if (job.state === 'claimed' && job.claimed_at <= now - STALE_MS) job.state = 'uncertain';
        if (job.state === 'queued' && job.due_at < now - LATE_MS) job.state = 'failed';
      }
    },
  };
}

const queue = fakeKV();
const epoch = Date.parse('2099-12-01T00:00:00Z');
let ms = epoch, sent = 0, prepared = 0;
const registry = new Map([['noop-test', {
  cloud: true,
  prepareAheadMs: 20 * 60_000,
  prepare() { prepared++; return { id: 'container', expiresAt: epoch + 180_000 }; },
  publish(item, { preparedId }) {
    if (item.ref === 'act-20991201-deadbeef') assert.equal(preparedId, 'container');
    assert.equal(new TextDecoder().decode(item.text), 'Caption');
    sent++;
    return { result: 'ok', remoteId: 'fixture-id' };
  },
}]]);
const item = {
  ref: 'act-20991201-deadbeef', digest: 'a'.repeat(64), due_at: new Date(epoch + 120_000).toISOString(),
  action: 'noop-test', text: btoa('Caption'), media: [], attempt: 1,
};
const body = JSON.stringify({ op: 'enqueue', item });
const submit = (body, signature) => accept(new Request('http://127.0.0.1/queue', {
  method: 'POST', headers: { 'x-kaito-signature': signature }, body,
}), queue, key, registry);
assert.equal((await submit(body, '0'.repeat(64))).status, 401);
const signature = await sign(key, body);
assert.equal((await submit(body.replace('noop-test', 'other-verb'), signature)).status, 401);
assert.equal((await submit(body, signature)).status, 200);
const tickOptions = { now: () => ms, registry };
await Promise.all([tick(queue, key, tickOptions), tick(queue, key, tickOptions)]);
assert.equal(sent, 0);
assert.equal(prepared, 1);
ms += 120_000;
await Promise.all([tick(queue, key, tickOptions), tick(queue, key, tickOptions)]);
assert.equal((await queue.status(item.ref)).state, 'ok');
await submit(body, signature);
await tick(queue, key, tickOptions);
assert.equal(sent, 1);

const interrupted = JSON.stringify({ op: 'enqueue', item: { ...item, ref: 'act-20991201-deadbeee' } });
await submit(interrupted, await sign(key, interrupted));
const crashing = { ...queue, async finish() { throw new Error('lost result'); } };
await assert.rejects(tick(crashing, key, tickOptions), /lost result/);
ms += STALE_MS + 1;
await tick(queue, key, tickOptions);
assert.equal((await queue.status('act-20991201-deadbeee')).state, 'uncertain');
assert.equal(sent, 2);

// Exercise the real D1 SQL through SQLite and the Mac's real sync CLI over loopback.
const sqlite = new DatabaseSync(':memory:');
sqlite.exec(fs.readFileSync(path.join(repo, 'business/worker/schema.sql'), 'utf8'));
const d1 = d1Queue({
  prepare(sql) {
    const stmt = sqlite.prepare(sql);
    return { bind: (...args) => ({
      first: () => stmt.get(...args),
      all: () => ({ results: stmt.all(...args) }),
      run: () => ({ meta: stmt.run(...args) }),
    }) };
  },
});
const cli = (name, ...args) => promisify(execFile)(process.execPath, [path.join(repo, 'business/scripts', `kaito-${name}.mjs`), ...args]);
const home = process.env.KAITO_HOME;
const ownerDir = path.join(home, 'owners/lumen-tea');
fs.mkdirSync(ownerDir, { recursive: true });
const owner = { id: 'lumen-tea', kind: 'company', name: 'Lumen Tea Co.', channels: { instagram: '@lumentea.example' }, cloud_ok: true };
fs.writeFileSync(path.join(ownerDir, 'owner.json'), JSON.stringify(owner));
const caption = path.join(home, 'caption');
fs.writeFileSync(caption, 'Fixture caption');
const due = Date.now() + 120_000;
const { stdout } = await cli('ledger', 'propose', '--owner', owner.id, '--account', owner.channels.instagram,
  '--action', 'noop-test', '--text-file', caption, '--due', new Date(due).toISOString().replace(/\.\d+Z$/, 'Z'), '--json');
const proposed = JSON.parse(stdout);
await promisify(execFile)(process.execPath, [path.join(repo, 'tests/fixtures/scheduler-approval.mjs'), repo, proposed.ref, proposed.digest]);
const keyFile = path.join(home, 'worker.key');
fs.writeFileSync(keyFile, secret, { mode: 0o600 });
const server = createServer(async (req, res) => {
  try {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const response = await accept(new Request('http://127.0.0.1/queue', {
      method: req.method, headers: req.headers, body: Buffer.concat(chunks),
    }), d1, key);
    res.writeHead(response.status);
    res.end(await response.text());
  } catch {
    res.writeHead(500);
    res.end();
  }
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
try {
  const cfg = { url: `http://127.0.0.1:${server.address().port}/queue`, key_file: keyFile, owners: [] };
  const configFile = path.join(home, 'business/worker.json');
  fs.writeFileSync(configFile, JSON.stringify(cfg));
  await assert.rejects(cli('tick', 'sync', proposed.ref), { code: 3 });
  fs.writeFileSync(configFile, JSON.stringify({ ...cfg, owners: [owner.id] }));
  assert.match((await cli('tick', 'sync', proposed.ref)).stdout, /delegated=/);
  await assert.rejects(cli('ledger', 'claim', proposed.ref, '--digest', proposed.digest), /already claimed/);
  await assert.rejects(cli('ledger', 'reconcile', proposed.ref, '--failed'), /may still be sending/);
  assert.equal((await cli('tick')).stdout, '');
  await tick(d1, key, { now: () => due - 60_000 });
  await Promise.all([tick(d1, key, { now: () => due }), tick(d1, key, { now: () => due })]);
  assert.match((await cli('tick')).stdout, /sent=/);
  const { stdout: status } = await cli('ledger', 'status', proposed.ref, '--json');
  assert.equal(JSON.parse(status).remote_id, `noop-prepared-${proposed.ref}`);
  assert.equal(sqlite.prepare('SELECT body FROM jobs WHERE ref = ?').get(proposed.ref).body, '');
  const local = openDb();
  assert.equal(local.prepare('SELECT count(*) AS n FROM attempts WHERE ref = ?').get(proposed.ref).n, 1);
  local.close();
} finally {
  await new Promise((resolve) => server.close(resolve));
  sqlite.close();
}
