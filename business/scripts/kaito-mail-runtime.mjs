import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { EXIT, fail, readOwner } from './kaito-ledger-lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));

export function businessCommand(name, args) {
  const result = spawnSync(process.execPath, [path.join(here, `kaito-${name}.mjs`), ...args], {
    encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
  });
  if (result.status !== 0) fail(result.status || EXIT.error, result.stderr?.trim() || `kaito-${name} failed`);
  return result.stdout;
}

export function resolveMailOwner(explicit) {
  const details = businessCommand('owner', ['resolve', ...(explicit ? ['--owner', explicit] : [])]);
  const owner = /^owner=(.+)$/m.exec(details)[1];
  const root = /^root=(.+)$/m.exec(details)[1];
  return { owner, root, record: readOwner(owner) };
}

export function readMailKey(record, engine) {
  const file = record.keys?.[engine];
  if (!file) fail(EXIT.notFound, `set keys.${engine} in owner.json to a key file path`);
  try {
    const key = JSON.parse(fs.readFileSync(file.startsWith('~/') ? path.join(os.homedir(), file.slice(2)) : file, 'utf8'));
    if (!key || typeof key !== 'object' || Array.isArray(key)) throw new Error();
    return key;
  } catch {
    fail(EXIT.error, `cannot read the ${engine} JSON key file`);
  }
}

export function readSupportInbox(input) {
  return spawnSync('python3', ['-I', path.join(here, 'kaito-support-read.py')], {
    input: JSON.stringify(input), encoding: 'utf8', timeout: 60_000, maxBuffer: 32 * 1024 * 1024,
    stdio: ['pipe', 'pipe', 'ignore'],
  });
}

export function requireMailConsent(owner, engine, args) {
  const consent = businessCommand('engines', ['consent', engine, '--owner', owner, '--status']);
  if (!args['allow-cloud'] || consent.trim() !== `${engine} for ${owner}: granted`) {
    fail(EXIT.human, `remote ${engine} needs --allow-cloud and the owner's ${engine} engine consent`);
  }
}
