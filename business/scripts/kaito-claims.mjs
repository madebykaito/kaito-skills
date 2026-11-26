#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { kaitoHome } from './kaito-ledger-lib.mjs';

const args = process.argv.slice(2);
if (args.length !== 4 || args[0] !== 'check' || args[1] !== '--owner' || !args[2] || !args[3]) {
  console.error('usage: kaito-claims.mjs check --owner <id> <post>'); process.exit(2);
}
const owner = spawnSync(process.execPath, [path.join(import.meta.dirname, 'kaito-owner.mjs'), 'resolve', '--owner', args[2]], { encoding: 'utf8' });
if (owner.status !== 0) { process.stderr.write(owner.stderr || owner.stdout); process.exit(owner.status ?? 1); }
try {
  const post = fs.readFileSync(args[3], 'utf8');
  const file = path.join(kaitoHome(), 'owners', args[2], 'evidence.json');
  let evidence = [];
  if (fs.existsSync(file)) evidence = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!Array.isArray(evidence)) throw new Error('evidence.json must be an array');
  const today = new Date().toISOString().slice(0, 10);
  const date = s => typeof s === 'string' && /^\d{4}-\d\d-\d\d$/.test(s) && !Number.isNaN(Date.parse(s)) && new Date(s).toISOString().slice(0, 10) === s;
  const valid = evidence.filter(e => e && typeof e.claim === 'string' && e.claim.trim() && typeof e.source === 'string' && e.source.trim() && date(e.date) && date(e.expiry) && e.date <= today && e.expiry >= today && e.expiry >= e.date);
  const pattern = /\b(?:\d+(?:[.,]\d+)*(?:\s*%|\b)|(?:\w+est|best|worst|leading|number\s+one|no\.\s*1)|health(?:y|ier|iest|ful)?|cures?|treats?|prevents?|made in|grown in|sourced from|originat(?:es?|ed)|award(?:ed| winning)?|won|certified|better than|more than|less than|unlike|compared (?:to|with))\b/gi;
  let failed = 0;
  post.split(/\r?\n/).forEach((line, i) => {
    const lower = line.toLowerCase();
    for (const match of line.matchAll(pattern)) {
      const backed = valid.some(e => {
        const claim = e.claim.trim().toLowerCase();
        let start = lower.indexOf(claim);
        while (start !== -1) {
          if (start <= match.index && start + claim.length >= match.index + match[0].length) return true;
          start = lower.indexOf(claim, start + 1);
        }
        return false;
      });
      if (!backed) { console.log(`${args[3]}:${i + 1}: unsourced or expired claim: ${line.trim()}`); failed++; break; }
    }
  });
  if (failed) process.exitCode = 1;
  else console.log('claims-check: detected claims have current evidence');
} catch (e) { console.error(`kaito-claims: ${e.message}`); process.exitCode = 1; }
