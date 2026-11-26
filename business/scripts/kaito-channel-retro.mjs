#!/usr/bin/env node
import fs from 'node:fs';
import { instagramRetro } from './kaito-instagram-retro.mjs';
import { EXIT, fail, run, parseArgs, only, openDb, checkOwnerId, readOwner } from './kaito-ledger-lib.mjs';

await run(async argv => {
  const a = parseArgs(argv); only(a, ['owner', 'start', 'end', 'website', 'fixture']);
  if (a._.length || !a.start || !a.end) fail(EXIT.usage, 'usage: kaito-channel-retro.mjs --owner id --start ISO --end ISO [--website id] [--fixture JSON]');
  const owner = checkOwnerId(a.owner);
  if (!readOwner(owner)) fail(EXIT.notFound, `owner not found: ${owner}`);
  const start = Date.parse(a.start), end = Date.parse(a.end);
  if (!Number.isFinite(start) || !Number.isFinite(end) || end - start !== 7 * 86400000) fail(EXIT.usage, 'interval must be seven days');
  let data;
  if (a.fixture) data = JSON.parse(fs.readFileSync(a.fixture, 'utf8'));
  else {
    const db = openDb();
    try {
      const rows = db.prepare('SELECT website_id, stats_json FROM umami_metrics WHERE owner=? AND start_at=? AND end_at=?').all(owner, new Date(start).toISOString(), new Date(end).toISOString());
      const found = a.website ? rows.filter(r => r.website_id === a.website) : rows;
      if (found.length > 1) fail(EXIT.human, 'multiple websites: select one with --website');
      data = {
        umami: found.length ? Object.fromEntries(Object.entries(JSON.parse(found[0].stats_json)).map(([k, v]) => [k, v.value])) : null,
        instagram: instagramRetro(db, owner, { start: new Date(start).toISOString().slice(0, 10), end: new Date(end).toISOString().slice(0, 10) }),
      };
    } finally { db.close(); }
  }
  console.log(`# Channel retro: ${owner}\n\n${new Date(start).toISOString()} to ${new Date(end).toISOString()} (end exclusive)`);
  for (const key of ['umami', 'instagram']) {
    console.log(`\n## ${key === 'umami' ? 'Website (Umami)' : 'Instagram'}\n`);
    const values = data?.[key];
    if (!values || typeof values !== 'object' || Array.isArray(values) || !Object.keys(values).length) { console.log('No data.'); continue; }
    for (const [name, value] of Object.entries(values)) {
      if (!/^[a-z][a-z0-9_]*$/.test(name) || typeof value !== 'number' || !Number.isFinite(value)) fail(EXIT.error, `invalid ${key} metric`);
      console.log(`- ${name}: ${value}`);
    }
  }
});
