import { cloudHandlers } from '../handlers/cloud-registry.mjs';
import { prepare, publish } from '../handlers/contract.mjs';
import { hmacKey, isRef, isSha, LATE_MS, readBody, verify } from './protocol.mjs';
import { d1Queue } from './d1-queue.mjs';

export async function accept(request, queue, key, registry = cloudHandlers) {
  const { pathname } = new URL(request.url);
  if (request.method !== 'POST' || pathname !== '/queue') return new Response(null, { status: 404 });
  const signature = request.headers.get('x-kaito-signature');
  if (!isSha(signature)) return new Response(null, { status: 401 });
  let body, envelope;
  try { body = await readBody(request); } catch { return new Response(null, { status: 400 }); }
  if (!await verify(key, body, signature)) return new Response(null, { status: 401 });
  try { envelope = JSON.parse(body); } catch { return new Response(null, { status: 400 }); }
  const fields = envelope?.op === 'enqueue' ? envelope.item : envelope;
  if (!isRef(fields?.ref) || !isSha(fields.digest)) return new Response(null, { status: 400 });
  const { ref, digest } = fields;
  if (envelope.op === 'enqueue') {
    const due_at = Date.parse(fields.due_at);
    if (!registry.get(fields.action)?.cloud || !Number.isFinite(due_at) || fields.attempt !== 1) {
      return new Response(null, { status: 400 });
    }
    await queue.enqueue({ ref, digest, body, signature, due_at });
  } else if (envelope.op !== 'status') return new Response(null, { status: 400 });
  const job = await queue.status(ref);
  if (job && job.digest !== digest) return new Response(null, { status: 409 });
  return Response.json({ state: job?.state ?? 'missing', remoteId: job?.remote_id ?? null });
}

async function checkedItem(job, key) {
  if (!await verify(key, job.body, job.signature)) throw new Error('invalid queue signature');
  const { item } = JSON.parse(job.body);
  if (item.ref !== job.ref || item.digest !== job.digest || Date.parse(item.due_at) !== job.due_at) {
    throw new Error('queue metadata does not match signed payload');
  }
  const decode = (value) => Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
  return { ...item, text: item.text == null ? null : decode(item.text), media: item.media.map(decode) };
}

export async function tick(queue, key, { now = Date.now, registry = cloudHandlers, env } = {}) {
  const at = now();
  await queue.sweep(at);
  for (const job of await queue.due(at)) {
    const claim = await queue.claim(job.ref, now());
    if (!claim) continue;
    let out = { result: 'failed', remoteId: null };
    try {
      const item = await checkedItem(job, key);
      const handler = registry.get(item.action);
      const sendAt = now();
      if (handler?.cloud && sendAt >= job.due_at && sendAt <= job.due_at + LATE_MS) {
        const preparedId = claim.prepared_until > sendAt ? claim.prepared_id : null;
        out = await publish(handler, item, { now, preparedId, env });
      }
    } catch {
      // A bad queue envelope fails before the handler runs.
    }
    await queue.finish(job.ref, out);
  }
  const lead = Math.max(0, ...Array.from(registry.values(), (handler) => handler.cloud ? handler.prepareAheadMs ?? 0 : 0));
  if (!lead) return;
  for (const job of await queue.upcoming(at, lead)) {
    try {
      const item = await checkedItem(job, key);
      const handler = registry.get(item.action);
      const start = now();
      if (!handler?.cloud || !handler.prepare || job.due_at - start > handler.prepareAheadMs) continue;
      if (!await queue.reservePreparation(job.ref, start)) continue;
      const { id, expiresAt } = await prepare(handler, item, { now, env });
      await queue.prepared(job.ref, start, id, expiresAt);
    } catch { console.error(`${job.ref}: Worker preparation failed`); }
  }
}

export default {
  async fetch(request, env) {
    return accept(request, d1Queue(env.QUEUE), await hmacKey(env.KAITO_QUEUE_HMAC));
  },
  async scheduled(_event, env) {
    await tick(d1Queue(env.QUEUE), await hmacKey(env.KAITO_QUEUE_HMAC), { env });
  },
};
