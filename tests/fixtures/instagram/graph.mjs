import assert from 'node:assert/strict';
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';

const [dir] = process.argv.slice(2);
const containers = new Map(), uploads = new Map(), media = [];
const log = (record) => appendFileSync(dir + '/requests', JSON.stringify(record) + '\n');
const account = '111';
let next = 200;
const server = createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const bytes = Buffer.concat(chunks);
  const params = req.method === 'POST' ? JSON.parse(bytes.toString()) : Object.fromEntries(url.searchParams);
  const send = (body, status = 200) => res.writeHead(status, { 'Content-Type': 'application/json' }).end(JSON.stringify(body));
  log({ method: req.method, path: url.pathname, params });
  try {
    if (req.method === 'GET' && /^[/]tunnel[/]kaito-ig-[a-zA-Z0-9]+[/][0-9a-f]{64}[.](jpg|mp4)$/.test(url.pathname)) {
      assert.equal(req.headers.authorization, undefined);
      return res.end(readFileSync(dir + url.pathname));
    }
    if (url.pathname.startsWith('/public/') && req.method === 'GET') {
      assert.equal(req.headers.authorization, undefined);
      const version = url.searchParams.get('versionId');
      const asset = uploads.get(url.pathname.slice(8))?.get(version);
      assert(asset);
      res.setHeader('x-amz-version-id', version);
      return res.end(readFileSync(dir + '/mode', 'utf8').trim() === 'wrong-bytes' ? Buffer.from('other asset') : asset);
    }
    if (url.pathname.startsWith('/upload/') && req.method === 'PUT') {
      assert.equal(req.headers.authorization, undefined);
      const key = url.pathname.slice(8);
      if (!uploads.has(key)) uploads.set(key, new Map());
      const versions = uploads.get(key);
      const version = String(versions.size + 1);
      versions.set(version, bytes);
      res.setHeader('x-amz-version-id', version);
      return send({});
    }
    assert.equal(req.headers.authorization, 'Bearer fixture-token');
    assert.equal(url.searchParams.has('access_token'), false);
    const [version, id, edge] = url.pathname.split('/').slice(1);
    assert.equal(version, 'v27.0');
    if (id === account && !edge) return send({ id, username: 'lumentea.example' });
    if (id === account && edge === 'media' && req.method === 'POST') {
      const type = params.media_type ?? 'IMAGE';
      for (const field of ['video_url', 'image_url', 'cover_url']) {
        if (!params[field]) continue;
        const source = new URL(params[field]);
        const result = await fetch(source);
        assert.equal(result.status, 200);
        assert((await result.arrayBuffer()).byteLength);
      }
      if (type === 'CAROUSEL') {
        for (const child of params.children.split(',')) {
          assert.equal(containers.get(child)?.params.is_carousel_item, true);
          assert.equal(containers.get(child)?.status, 'FINISHED');
        }
      }
      const cid = String(++next);
      containers.set(cid, { params, polls: 0, status: 'IN_PROGRESS' });
      return send({ id: cid });
    }
    if (containers.has(id) && !edge) {
      const container = containers.get(id);
      if (++container.polls > 1 && container.status !== 'PUBLISHED') container.status = 'FINISHED';
      return send({ status_code: container.status });
    }
    if (id === account && edge === 'media_publish') {
      const container = containers.get(params.creation_id);
      assert.equal(container.status, 'FINISHED');
      const mode = readFileSync(dir + '/mode', 'utf8').trim();
      if (mode === 'refuse') return send({ error: { code: 100, message: 'fixture-token' } }, 400);
      container.status = 'PUBLISHED';
      const type = container.params.media_type ?? 'IMAGE';
      const item = {
        id: String(++next), caption: container.params.caption,
        timestamp: new Date().toISOString(),
        media_product_type: { REELS: 'REELS', STORIES: 'STORY' }[type] ?? 'FEED',
        media_type: { REELS: 'VIDEO', CAROUSEL: 'CAROUSEL_ALBUM', STORIES: container.params.video_url ? 'VIDEO' : 'IMAGE' }[type] ?? 'IMAGE',
      };
      media.unshift(item);
      if (mode === 'lose') return req.socket.destroy();
      return send({ id: item.id });
    }
    if (id === account && edge === 'media') {
      const older = { id: '951', caption: media[0]?.caption, timestamp: '2021-01-01T00:00:00Z', media_type: 'IMAGE', media_product_type: 'FEED' };
      if (params.after === 'rest') return send({ data: [...media.filter((m) => m.media_product_type !== 'STORY'), older] });
      return send({ data: [], paging: { next: 'https://invalid.example/?access_token=fixture-token', cursors: { after: 'rest' } } });
    }
    if (id === account && edge === 'stories') return send({ data: media.filter((m) => m.media_product_type === 'STORY') });
    if (edge === 'insights' && id === '951') return send({ error: { code: 100, error_subcode: 2108006 } }, 400);
    if (edge === 'insights' && id === account) {
      assert.equal(params.period, 'day');
      return send({ data: params.metric.split(',').map((name) => ({ name, period: 'day',
        ...(params.metric_type === 'total_value' ? { total_value: { value: 23 } } : { values: [{ value: 12, end_time: '2026-11-26T08:00:00+0000' }] }),
      })) });
    }
    if (edge === 'insights' && media.some((m) => m.id === id)) {
      return send({ data: params.metric.split(',').map((name) => ({ name, period: 'lifetime', values: [{ value: 7 }] })) });
    }
    return send({ error: { code: 100 } }, 400);
  } catch (err) {
    console.error(err.message);
    return send({ error: { code: 2, is_transient: true } }, 500);
  }
});
server.listen(0, '127.0.0.1', () => writeFileSync(dir + '/port', String(server.address().port)));
