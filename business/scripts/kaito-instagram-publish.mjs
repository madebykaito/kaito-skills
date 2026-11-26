#!/usr/bin/env node
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import {
  canonicalText, EXIT, fail, isSha, only, openDb, parseArgs, printKv, run, sha256,
} from './kaito-ledger-lib.mjs';
import { instagramGraph, instagramOwner, isId, ledger } from './kaito-instagram-graph.mjs';
import { mediaType } from './kaito-instagram-media.mjs';
import { actionFor, kindOf, kinds, MAX_CAROUSEL, validatePayload } from './kaito-instagram-payload.mjs';
import { instagramPublishHandlers } from '../handlers/instagram-publish.mjs';

const USAGE = `usage:
  kaito-instagram-publish.mjs preflight <video>
  kaito-instagram-publish.mjs propose image|reel|story|carousel --media <file ...> [--owner <id>] [--caption-file <file>]
      [--disclosure ai|none] [--due <time>] [--location-id <id>] [--collaborator <username ...>]
      [--cover <jpeg> | --thumb-offset <ms>] [--retry-of <ref>] [--json]
  kaito-instagram-publish.mjs publish <ref> --digest <sha256>
  kaito-instagram-publish.mjs reconcile <ref>`;

function localFile(file, label, maxBytes) {
  try {
    const info = statSync(file);
    if (!info.isFile() || info.size > maxBytes) fail(EXIT.usage, `${label} must be a file no larger than ${maxBytes} bytes`);
  } catch (error) {
    if (error.code === EXIT.usage) throw error;
    fail(EXIT.usage, `Cannot read ${label}`);
  }
  try { return readFileSync(file); } catch { fail(EXIT.usage, `Cannot read ${label}`); }
}

function propose(kind, args) {
  only(args, ['owner', 'media', 'caption-file', 'disclosure', 'due', 'location-id', 'collaborator', 'cover', 'thumb-offset', 'retry-of', 'json']);
  if (!kinds.includes(kind) || !args.media?.length) fail(EXIT.usage, USAGE);
  const owner = instagramOwner(args.owner);
  const max = kind === 'carousel' ? MAX_CAROUSEL : 1;
  if (args.media.length > max) fail(EXIT.usage, `Instagram ${kind} accepts at most ${max} media files`);
  const files = args.cover ? [...args.media, args.cover] : args.media;
  const options = validatePayload(kind, {
    v: 1,
    caption: args['caption-file'] ? canonicalText(localFile(args['caption-file'], 'caption', 16_384)).toString() : '',
    type: args.media.map((file) => mediaType(localFile(file, 'media', 300_000_000),
      kind === 'image' ? 'image' : kind === 'reel' ? 'video' : undefined, kind)),
    collaborators: (args.collaborator ?? []).map((user) => user.replace(/^@/, '')),
    ...(args.cover && { cover: true }),
    ...(args['location-id'] !== undefined && { location_id: args['location-id'] }),
    ...(args['thumb-offset'] !== undefined && {
      thumb_offset: /^\d+$/.test(args['thumb-offset']) ? Number(args['thumb-offset']) : NaN,
    }),
  }, files.length);
  if (args.cover) mediaType(localFile(args.cover, 'cover', 300_000_000), 'image');

  const dir = mkdtempSync(path.join(tmpdir(), 'kaito-instagram-proposal-'));
  try {
    const payload = path.join(dir, 'instagram-post.json');
    writeFileSync(payload, JSON.stringify(options, null, 2) + '\n', { mode: 0o600 });
    const command = ['propose', '--owner', owner.id, '--account', owner.account, '--action', actionFor(kind),
      '--text-file', payload, ...files.map((file) => `--media=${file}`)];
    for (const flag of ['disclosure', 'due', 'retry-of']) {
      if (args[flag] !== undefined) command.push(`--${flag}=${args[flag]}`);
    }
    process.stdout.write(ledger([...command, ...(args.json ? ['--json'] : [])]));
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

async function publish(ref, digest) {
  if (!isSha(digest)) fail(EXIT.usage, 'publish needs --digest <full sha256>');
  const row = ledger(['status', ref], true);
  const handler = instagramPublishHandlers.get(row.action);
  if (!handler) fail(EXIT.usage, 'This ledger ref is not an Instagram publish action');
  const claim = ledger(['claim', ref, '--digest', digest], true);
  const out = await handler.publish(ref, digest, claim.attempt);
  process.stdout.write(ledger(['record', ref, '--attempt', String(claim.attempt), '--result', out.result,
    ...(out.remoteId ? ['--remote-id', out.remoteId] : []), ...(out.note ? ['--note', out.note] : [])]));
  if (out.result === 'ok') printKv({ remote_id: out.remoteId });
  if (out.result === 'failed') fail(EXIT.error, out.note ?? 'Instagram publish failed before acceptance');
  if (out.result === 'uncertain') fail(EXIT.human, `Instagram publish is uncertain. Check with reconcile ${ref}`);
}

function matchType(kind, media) {
  if (kind === 'reel') return media.media_product_type === 'REELS' && media.media_type === 'VIDEO';
  return media.media_product_type === 'FEED' && media.media_type === (kind === 'image' ? 'IMAGE' : 'CAROUSEL_ALBUM');
}

async function reconcile(ref) {
  const status = ledger(['status', ref], true);
  const kind = kindOf(status.action);
  if (!kind) fail(EXIT.usage, 'This ledger ref is not an Instagram publish action');
  const pending = ledger(['reconcile', '--owner', status.owner], true);
  if (!pending.some((row) => row.ref === ref)) fail(EXIT.human, 'Instagram ref is neither uncertain nor a stale claim');

  const db = openDb();
  let request, known;
  try {
    request = db.prepare('SELECT * FROM instagram_publish_requests WHERE ref = ?').get(ref);
    if (!request) fail(EXIT.human, 'No persisted Instagram publish request. Check the post on Instagram and reconcile manually');
    if (kind === 'story' || request.caption_sha256 === sha256('')) {
      fail(EXIT.human, 'Captionless Instagram posts need manual reconciliation');
    }
    const other = db.prepare(`SELECT 1 FROM instagram_publish_requests r JOIN actions a USING (ref)
      WHERE r.ref <> ? AND r.ig_user_id = ? AND r.caption_sha256 = ? AND a.action = ?
        AND a.state IN ('claimed', 'uncertain') AND abs(unixepoch(r.requested_at) - unixepoch(?)) <= 1200`)
      .get(ref, request.ig_user_id, request.caption_sha256, status.action, request.requested_at);
    if (other) fail(EXIT.human, 'Overlapping Instagram requests share this caption. Reconcile manually');
    known = new Set(db.prepare("SELECT remote_id FROM actions WHERE action GLOB 'instagram.*.publish' AND remote_id IS NOT NULL")
      .all().map((row) => row.remote_id));
  } finally { db.close(); }

  const owner = instagramOwner(status.owner);
  if (owner.account !== status.account) fail(EXIT.human, 'The ledger account differs from channels.instagram');
  const graph = await instagramGraph(owner);
  if (graph.id !== request.ig_user_id) fail(EXIT.human, 'Instagram account ID changed since the publish request');
  const container = await graph.request(request.container_id, { fields: 'status_code' });
  if (container.status_code !== 'PUBLISHED') fail(EXIT.human, 'Instagram has not confirmed the container as published');

  const started = Date.parse(request.requested_at);
  const matches = new Set();
  for await (const batch of graph.pages(`${graph.id}/media`, {
    fields: 'id,caption,timestamp,media_type,media_product_type', limit: 50,
  }, 10)) {
    // Meta orders this edge newest first. Stop once we've scanned the request window.
    let older = false;
    for (const item of batch) {
      const posted = Date.parse(item.timestamp);
      if (posted < started) older = true;
      if (posted >= started && posted <= started + 20 * 60_000 && isId(item.id) && !known.has(item.id) &&
          typeof item.caption === 'string' && sha256(item.caption) === request.caption_sha256 &&
          matchType(kind, item)) matches.add(item.id);
    }
    if (older) break;
  }
  if (matches.size !== 1) fail(EXIT.human, `Instagram reconciliation found ${matches.size} unique matches. Check the post manually`);
  const [id] = matches;
  process.stdout.write(ledger(['reconcile', ref, '--sent', '--remote-id', id]));
  printKv({ remote_id: id });
}

await run(async (argv) => {
  if (argv.length === 1 && argv[0] === '--help') { console.log(USAGE); return; }
  const args = parseArgs(argv, { multi: ['media', 'collaborator'], bool: ['json'] });
  const [cmd, arg] = args._;
  if (!arg || args._.length !== 2) fail(EXIT.usage, USAGE);
  if (cmd === 'propose') return propose(arg, args);
  if (cmd === 'preflight') {
    only(args, []);
    mediaType(localFile(arg, 'video', 300_000_000), 'video');
    console.log('Instagram video preflight passed');
    return;
  }
  if (cmd === 'publish') {
    only(args, ['digest']);
    return publish(arg, args.digest);
  }
  if (cmd === 'reconcile') {
    only(args, []);
    return reconcile(arg);
  }
  fail(EXIT.usage, USAGE);
});
