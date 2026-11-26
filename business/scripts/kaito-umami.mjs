#!/usr/bin/env node
import fs from 'node:fs';
import { EXIT, fail, run, parseArgs, only, openDb, checkOwnerId, readOwner } from './kaito-ledger-lib.mjs';

await run(async (argv) => {
  const a = parseArgs(argv);
  only(a, ['owner', 'website', 'start', 'end', 'url', 'key-file']);
  if (a._.length !== 1 || a._[0] !== 'pull' || !a.website || !a.start || !a.end || !a['key-file']) fail(EXIT.usage, 'usage: kaito-umami.mjs pull --owner id --website id --start ISO --end ISO --url API-base --key-file path');
  const owner = checkOwnerId(a.owner);
  if (!readOwner(owner)) fail(EXIT.notFound, `owner not found: ${owner}`);
  const start = Date.parse(a.start), end = Date.parse(a.end);
  if (!Number.isFinite(start) || !Number.isFinite(end) || start >= end) fail(EXIT.usage, 'invalid interval');
  const base = new URL(a.url || process.env.UMAMI_URL || 'http://127.0.0.1:3000/api');
  if (!['http:', 'https:'].includes(base.protocol) || base.username || base.password || base.search || base.hash) fail(EXIT.usage, 'invalid API base URL');
  if (!['localhost', '127.0.0.1', '[::1]'].includes(base.hostname) && base.protocol !== 'https:') fail(EXIT.usage, 'remote API requires HTTPS');
  const key = fs.readFileSync(a['key-file'], 'utf8').trim();
  if (!key || /[\r\n]/.test(key)) fail(EXIT.usage, 'key file must contain one API key');
  const url = new URL(`${base.pathname.replace(/\/$/, '')}/websites/${encodeURIComponent(a.website)}/stats`, base);
  url.searchParams.set('startAt', String(start)); url.searchParams.set('endAt', String(end));
  const res = await fetch(url, { headers: { Authorization: `Bearer ${key}`, Accept: 'application/json' }, redirect: 'error', signal: AbortSignal.timeout(30000) });
  if (!res.ok) fail(EXIT.error, `Umami returned HTTP ${res.status}`);
  const stats = await res.json();
  if (!stats || typeof stats !== 'object' || Array.isArray(stats) || !['pageviews', 'visitors'].every(k => Number.isFinite(stats[k]?.value))) fail(EXIT.error, 'invalid Umami statistics response');
  const db = openDb();
  db.prepare('INSERT INTO umami_metrics VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(owner, website_id, start_at, end_at) DO UPDATE SET stats_json=excluded.stats_json, pulled_at=excluded.pulled_at').run(owner, a.website, new Date(start).toISOString(), new Date(end).toISOString(), JSON.stringify(stats), new Date().toISOString());
  console.log('pulled=1');
});
