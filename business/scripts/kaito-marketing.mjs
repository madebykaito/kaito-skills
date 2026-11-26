#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { openDb } from './kaito-ledger-lib.mjs';
import { instagramRetro } from './kaito-instagram-retro.mjs';
import { spawnSync } from 'node:child_process';
const [cmd, ...rest] = process.argv.slice(2);
const flags = {};
for (let i = 0; i < rest.length; i += 2) {
  if (!rest[i]?.startsWith('--') || !rest[i + 1] || flags[rest[i]]) { console.error('invalid arguments'); process.exit(2); }
  flags[rest[i]] = rest[i + 1];
}
const required = cmd === 'review' ? ['--owner', '--brief', '--post'] : cmd === 'retro' ? ['--owner', '--brief'] : [];
const allowed = cmd === 'retro' ? [...required, '--metrics'] : required;
if (!allowed.length || required.some(k => !flags[k]) || Object.keys(flags).some(k => !allowed.includes(k))) {
  console.error('usage: kaito-marketing.mjs review --owner <id> --brief <json> --post <file> | retro --owner <id> --brief <json> [--metrics <json>]'); process.exit(2);
}
const owner = spawnSync(process.execPath, [path.join(import.meta.dirname, 'kaito-owner.mjs'), 'resolve', '--owner', flags['--owner']], { encoding: 'utf8' });
if (owner.status !== 0) { process.stderr.write(owner.stderr || owner.stdout); process.exit(owner.status ?? 1); }
try {
  const brief = JSON.parse(fs.readFileSync(flags['--brief'], 'utf8'));
  if (cmd === 'review') {
    if (!['buyer', 'message', 'action'].every(k => typeof brief[k] === 'string' && brief[k].trim())) throw new Error('brief needs buyer, message and action');
    const post = fs.readFileSync(flags['--post'], 'utf8');
    const claims = spawnSync(process.execPath, [path.join(import.meta.dirname, 'kaito-claims.mjs'), 'check', '--owner', flags['--owner'], flags['--post']], { encoding: 'utf8' });
    process.stdout.write(claims.stdout); process.stderr.write(claims.stderr);
    const missing = ['message', 'action'].filter(k => !post.toLowerCase().includes(brief[k].toLowerCase()));
    for (const k of missing) console.log(`FAIL: brief ${k} is not present verbatim; review alignment manually`);
    if (missing.length || claims.status !== 0) { console.log('FAIL'); process.exitCode = 1; }
    else console.log('Mechanical checks passed; human review of buyer, voice, proof and intent is required.');
  } else {
    if (typeof brief.metric !== 'string' || !brief.metric || !Number.isFinite(brief.target)) throw new Error('brief needs metric and numeric target');
    let metrics;
    if (flags['--metrics']) metrics = JSON.parse(fs.readFileSync(flags['--metrics'], 'utf8'));
    else {
      const { start, end, subject } = brief.instagram ?? {};
      if ([start, end].some(date => date !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(date)) ||
          (start && end && start >= end) || (subject !== undefined && !/^\d+$/.test(subject))) {
        throw new Error('brief.instagram needs an optional media subject ID and ISO dates with an exclusive end');
      }
      const db = openDb();
      try { metrics = instagramRetro(db, flags['--owner'], { start, end, subject }); }
      finally { db.close(); }
    }
    const value = metrics?.[brief.metric];
    if (!Number.isFinite(value)) throw new Error(`missing numeric metric: ${brief.metric}`);
    console.log(`# Marketing retro\n\n${brief.metric}: ${value}; target: ${brief.target}. ${value > brief.target ? 'Beat' : value === brief.target ? 'Met' : 'Missed'} the target.\n\nReview the period, source, what to repeat and what to stop. Treat explanations as hypotheses.`);
  }
} catch (e) { console.error(`kaito-marketing: ${e.message}`); process.exitCode = 1; }
