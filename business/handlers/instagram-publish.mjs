import { setTimeout as wait } from 'node:timers/promises';
import { EXIT, Fail, fail, getAction, isoUtc, openDb, sha256, tx } from '../scripts/kaito-ledger-lib.mjs';
import { GraphError, instagramGraph, instagramOwner, isId } from '../scripts/kaito-instagram-graph.mjs';
import { mediaType, uploadTarget } from '../scripts/kaito-instagram-media.mjs';
import { activeAttempt, consumeDispatch, verifiedItem } from './dispatch.mjs';
import { actionFor, kinds, readPayload } from '../scripts/kaito-instagram-payload.mjs';

async function graphFor(item, signal) {
  const owner = instagramOwner(item.owner);
  if (owner.account !== item.account) fail(EXIT.human, 'The ledger account differs from channels.instagram');
  return instagramGraph(owner, signal);
}

async function poll(graph, id, signal) {
  const testPause = +process.env.KAITO_INSTAGRAM_POLL_MS;
  const interval = graph.local && testPause > 0 && testPause <= 10_000 ? testPause : 60_000;
  for (let i = 0; i <= 5; i++) {
    const { status_code: status } = await graph.request(id, { fields: 'status_code' });
    if (status !== 'IN_PROGRESS') return status;
    if (i < 5) await wait(interval, undefined, { signal });
  }
  fail(EXIT.error, 'Instagram container is still processing after polling');
}

async function create(graph, params) {
  const { id } = await graph.request(`${graph.id}/media`, params, 'POST');
  if (!isId(id)) fail(EXIT.error, 'Instagram container response is missing its ID');
  return id;
}

async function finished(graph, id, signal) {
  const status = await poll(graph, id, signal);
  if (status !== 'FINISHED') fail(EXIT.error, 'Instagram container did not finish processing');
  return id;
}

async function prepareContainer(graph, item, kind, options, signal) {
  const types = [...options.type, ...(options.cover ? ['image'] : [])];
  // Validate all the approved media before sending any of it.
  item.media.forEach((bytes, index) => mediaType(bytes, types[index], kind));
  const digests = item.media.map(sha256);
  const target = uploadTarget(graph, digests, signal);
  try {
    const urls = [];
    for (let i = 0; i < types.length; i++) urls.push(await target.store(item.media[i], digests[i], types[i]));
    const media = (index) => ({ [types[index] === 'video' ? 'video_url' : 'image_url']: urls[index] });
    const common = {
      ...(options.caption && { caption: options.caption }),
      ...(item.disclosure === 'ai' && { is_ai_generated: true }),
      ...(options.location_id && { location_id: options.location_id }),
      ...(options.collaborators.length && { collaborators: options.collaborators }),
    };
    let params;
    if (kind === 'carousel') {
      const children = [];
      for (let i = 0; i < options.type.length; i++) {
        const id = await create(graph, {
          ...media(i), is_carousel_item: true, ...(types[i] === 'video' && { media_type: 'VIDEO' }),
        });
        children.push(id);
      }
      await Promise.all(children.map((id) => finished(graph, id, signal)));
      params = { media_type: 'CAROUSEL', children: children.join(',') };
    } else {
      params = {
        ...media(0),
        ...(kind === 'story' && { media_type: 'STORIES' }),
        ...(kind === 'reel' && { media_type: 'REELS' }),
        ...(options.cover && { cover_url: urls[1] }),
        ...(options.thumb_offset !== undefined && { thumb_offset: options.thumb_offset }),
      };
    }
    return await finished(graph, await create(graph, { ...params, ...common }), signal);
  } finally { target.close(); }
}

function recordRequest(item, graph, containerId, caption, signal) {
  const db = openDb();
  try {
    tx(db, () => {
      signal.throwIfAborted();
      activeAttempt(db, item.ref, item.digest, item.attempt);
      if (getAction(db, item.ref).state !== 'claimed') fail(EXIT.human, 'Instagram ledger claim is no longer active');
      db.prepare('INSERT INTO instagram_publish_requests VALUES (?, ?, ?, ?, ?)')
        .run(item.ref, graph.id, containerId, sha256(caption), isoUtc(Date.now()));
    });
  } finally { db.close(); }
}

function preparedContainer(item, graph) {
  const db = openDb();
  try {
    return db.prepare(`SELECT container_id FROM instagram_prepared_containers
      WHERE ref = ? AND digest = ? AND account = ? AND ig_user_id = ? AND expires_at > ?`)
      .get(item.ref, item.digest, item.account, graph.id, Date.now())?.container_id;
  } finally { db.close(); }
}

async function publish(ref, digest, attempt) {
  const item = consumeDispatch(ref, digest, attempt, (action) => kinds.some((kind) => actionFor(kind) === action));
  const signal = AbortSignal.timeout(20 * 60_000);
  let publishRequested = false;
  try {
    const { kind, options } = readPayload(item);
    const graph = await graphFor(item, signal);
    const prepared = preparedContainer(item, graph);
    let id;
    if (isId(prepared)) {
      const status = await poll(graph, prepared, signal).catch((error) => {
        if (!(error instanceof GraphError) || !error.definitive) throw error;
        return 'UNAVAILABLE';
      });
      if (status === 'FINISHED') id = prepared;
      if (status === 'PUBLISHED') return { result: 'uncertain' };
    }
    id ??= await prepareContainer(graph, item, kind, options, signal);
    // Write the intent before the only POST that can publish a container.
    recordRequest(item, graph, id, options.caption, signal);
    publishRequested = true;
    const result = await graph.request(`${graph.id}/media_publish`, { creation_id: id }, 'POST');
    return isId(result.id) ? { result: 'ok', remoteId: result.id } : { result: 'uncertain', note: 'missing published media ID' };
  } catch (error) {
    // A concurrent invocation may have persisted the request first.
    const db = openDb();
    let otherRequest;
    try { otherRequest = !publishRequested && db.prepare('SELECT 1 FROM instagram_publish_requests WHERE ref = ?').get(item.ref); }
    finally { db.close(); }
    const result = otherRequest || (publishRequested && !(error instanceof GraphError && error.definitive)) ? 'uncertain' : 'failed';
    return { result, note: error instanceof Fail ? error.message : 'Instagram operation could not complete' };
  }
}

async function prepare(ref, digest) {
  const started = Date.now();
  const db = openDb();
  try {
    const row = getAction(db, ref);
    const approval = db.prepare('SELECT 1 FROM approvals WHERE ref = ? AND digest = ?').get(ref, digest);
    if (row.state !== 'approved' || row.digest !== digest || row.action !== actionFor('reel') || !approval) {
      fail(EXIT.human, 'Instagram preparation needs an intact, approved Reel ref');
    }
    const item = verifiedItem(row);
    const signal = AbortSignal.timeout(20 * 60_000);
    const { kind, options } = readPayload(item);
    const graph = await graphFor(item, signal);
    const id = await prepareContainer(graph, item, kind, options, signal);
    // Meta containers expire after 24 hours. Count conservatively from before creation.
    const expiresAt = started + 23 * 3600_000;
    tx(db, () => {
      if (getAction(db, ref).state !== 'approved') fail(EXIT.human, 'Instagram ref is no longer approved for preparation');
      db.prepare(`INSERT INTO instagram_prepared_containers VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(ref) DO UPDATE SET ig_user_id = excluded.ig_user_id,
          container_id = excluded.container_id, expires_at = excluded.expires_at
        WHERE instagram_prepared_containers.expires_at <= excluded.expires_at`)
        .run(ref, digest, item.account, graph.id, id, expiresAt);
    });
    return { id: `${graph.id}:${id}`, expiresAt };
  } finally { db.close(); }
}

export const instagramPublishHandlers = new Map(kinds.map((kind) => [
  actionFor(kind),
  kind === 'reel' ? { ledger: true, publish, prepare, prepareAheadMs: 20 * 60_000 } : { ledger: true, publish },
]));
