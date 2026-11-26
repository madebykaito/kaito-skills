#!/bin/sh
. "$(dirname "$0")/lib.sh"

test_hosted_media_pins_and_verifies_uploaded_version() {
  mk_home
  node --input-type=module - "$REPO/business/scripts/kaito-instagram-media.mjs" <<'NODE'
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';

const { uploadTarget } = await import(pathToFileURL(process.argv[2]));
const versions = new Map();
let latest, mode;
const server = createServer(async (req, res) => {
  if (req.method === 'PUT') {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    latest = `v+/${versions.size + 1}`;
    versions.set(latest, Buffer.concat(chunks));
    if (mode !== 'unversioned') res.setHeader('x-amz-version-id', latest);
    return res.end();
  }
  const url = new URL(req.url, 'http://localhost');
  const selected = url.searchParams.get('versionId') || latest;
  if (mode !== 'unconfirmed') res.setHeader('x-amz-version-id', selected);
  res.end(versions.get(selected));
});
server.listen(0, '127.0.0.1');
await once(server, 'listening');
const url = `http://127.0.0.1:${server.address().port}/media`;
function store(bytes) {
  const digest = createHash('sha256').update(bytes).digest('hex');
  const graph = { local: true, upload: { kind: 'presigned-put', objects: {
    [digest]: { put_url: url, read_url: url },
  } } };
  return uploadTarget(graph, [digest]).store(bytes, digest, 'image');
}

try {
  const first = Buffer.from('first fixture');
  const second = Buffer.from('second fixture');
  const firstUrl = await store(first);
  const secondUrl = await store(second);
  assert.equal(new URL(firstUrl).searchParams.get('versionId'), 'v+/1');
  assert.equal(new URL(secondUrl).searchParams.get('versionId'), 'v+/2');
  for (const [source, expected] of [[firstUrl, first], [secondUrl, second]]) {
    assert.deepEqual(Buffer.from(await (await fetch(source)).arrayBuffer()), expected);
  }
  mode = 'unversioned';
  await assert.rejects(store(first), /immutable object version/);
  mode = 'unconfirmed';
  await assert.rejects(store(first), /did not confirm the uploaded version/);
} finally {
  server.close();
}
NODE
}
