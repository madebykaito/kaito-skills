#!/usr/bin/env node
// Owner records for business work: whose brand a job is for, and where that owner's files and memory live.
// Usage: kaito-owner.mjs resolve [--owner <id>] [--cwd <dir>]
//        | list [--json]
//        | add <id> --name <name> --kind company|person [--locale <tag>] [--timezone <tz>] [--currency <ISO>] [--gstin <no>]
//        | show [<id>] [--cwd <dir>]
//        | bind <id> <dir> | unbind <dir>
// Owners live in $KAITO_HOME/owners/<id>/owner.json (KAITO_HOME defaults to ~/.kaito).
// Exit codes: 0 ok, 1 error (a bad record, a refused write), 2 usage, 3 needs a human decision (ambiguous), 4 not found.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const K = process.env.KAITO_HOME || path.join(os.homedir(), '.kaito');
const OWNERS = path.join(K, 'owners');
const ID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const FIELDS = new Set(['id', 'name', 'kind', 'locale', 'timezone', 'currency', 'gstin', 'bindings', 'channels', 'keys', 'memory_root', 'cloud_ok']);

class Exit extends Error { constructor(code, msg) { super(msg); this.code = code; } }
const fail = (code, msg) => { throw new Exit(code, msg); };
const USAGE = 'usage: kaito-owner.mjs resolve [--owner <id>] [--cwd <dir>] | list [--json] | add <id> --name <name> --kind company|person [--locale <tag>] [--timezone <tz>] [--currency <ISO>] [--gstin <no>] | show [<id>] [--cwd <dir>] | bind <id> <dir> | unbind <dir>';

function checkId(id, what = 'owner id') {
  if (typeof id !== 'string' || id.length > 64 || !ID.test(id)) {
    fail(2, `${what} must be kebab-case (a-z, 0-9 and single hyphens, at most 64 characters): ${JSON.stringify(id)}`);
  }
  return id;
}

const home = (p) => (p === '~' ? os.homedir() : p.startsWith('~/') ? path.join(os.homedir(), p.slice(2)) : p);
// The real path when it exists, so /var and /private/var (or a symlinked folder) compare equal.
function real(p) {
  const abs = path.resolve(home(p));
  try { return fs.realpathSync.native(abs); } catch { return abs; }
}
// a is b or inside b
function within(a, b) {
  const r = path.relative(b, a);
  return r === '' || (r !== '..' && !r.startsWith(`..${path.sep}`) && !path.isAbsolute(r));
}
const depth = (p) => p.split(path.sep).filter(Boolean).length;

function validTimezone(tz) {
  try { new Intl.DateTimeFormat('en', { timeZone: tz }); return true; } catch { return false; }
}

// Returns a list of problems; an empty list is a valid record.
function problems(o, folderId) {
  const bad = [];
  if (!o || typeof o !== 'object' || Array.isArray(o)) return ['owner.json must hold one JSON object'];
  for (const k of Object.keys(o)) if (!FIELDS.has(k)) bad.push(`unknown field "${k}"`);
  if (typeof o.id !== 'string' || !ID.test(o.id) || o.id.length > 64) bad.push('id must be kebab-case');
  else if (folderId && o.id !== folderId) bad.push(`id "${o.id}" does not match its folder "${folderId}"`);
  if (typeof o.name !== 'string' || !o.name.trim()) bad.push('name is required');
  if (o.kind !== 'company' && o.kind !== 'person') bad.push('kind must be company or person');
  if (o.locale !== undefined && (typeof o.locale !== 'string' || !/^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(o.locale))) bad.push('locale must be a language tag such as en-IN');
  if (o.timezone !== undefined && (typeof o.timezone !== 'string' || !validTimezone(o.timezone))) bad.push('timezone must be an IANA zone such as Asia/Kolkata');
  if (o.currency !== undefined && (typeof o.currency !== 'string' || !/^[A-Z]{3}$/.test(o.currency))) bad.push('currency must be a three-letter ISO code such as INR');
  if (o.gstin !== undefined && o.gstin !== null && (typeof o.gstin !== 'string' || !/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/.test(o.gstin))) bad.push('gstin must be 15 characters in the GSTIN pattern, such as 19ABCDE1234F1Z5');
  if (o.bindings !== undefined && (!Array.isArray(o.bindings) || o.bindings.some((b) => typeof b !== 'string' || !path.isAbsolute(b)))) bad.push('bindings must be a list of absolute folder paths');
  for (const f of ['channels', 'keys']) {
    const v = o[f];
    if (v === undefined) continue;
    if (!v || typeof v !== 'object' || Array.isArray(v) || Object.values(v).some((x) => typeof x !== 'string' || !x)) bad.push(`${f} must be an object of names to strings`);
  }
  // keys name key files, never hold the value
  if (o.keys && typeof o.keys === 'object') {
    for (const [k, v] of Object.entries(o.keys)) {
      if (typeof v === 'string' && !(v.startsWith('/') || v.startsWith('~/'))) bad.push(`keys.${k} must be the path of a key file (absolute or ~/), never the key itself`);
    }
  }
  if (o.memory_root !== undefined && (typeof o.memory_root !== 'string' || !(path.isAbsolute(o.memory_root) || o.memory_root.startsWith('~/')))) bad.push('memory_root must be an absolute or ~/ path');
  if (o.cloud_ok !== undefined && typeof o.cloud_ok !== 'boolean') bad.push('cloud_ok must be true or false');
  return bad;
}

function root(id) { return path.join(OWNERS, checkId(id)); }
function memoryDir(o) { return o.memory_root ? path.resolve(home(o.memory_root)) : path.join(OWNERS, o.id, 'memory'); }

function readOwner(id) {
  const f = path.join(root(id), 'owner.json');
  let text;
  try { text = fs.readFileSync(f, 'utf8'); } catch (e) {
    if (e.code === 'ENOENT') return null;
    fail(1, `cannot read ${f}: ${e.message}`);
  }
  let o;
  try { o = JSON.parse(text); } catch (e) { fail(1, `${f} is not valid JSON: ${e.message}`); }
  const bad = problems(o, id);
  if (bad.length) fail(1, `${f}: ${bad.join('; ')}`);
  return o;
}

// Every owner. A broken record stops everything: resolving around it could pick the wrong owner.
function allOwners() {
  let names;
  try { names = fs.readdirSync(OWNERS, { withFileTypes: true }); } catch (e) {
    if (e.code === 'ENOENT') return [];
    fail(1, `cannot read ${OWNERS}: ${e.message}`);
  }
  const list = [];
  for (const d of names) {
    if (d.name.startsWith('.') || !d.isDirectory()) continue;
    if (!ID.test(d.name)) fail(1, `${path.join(OWNERS, d.name)}: an owner folder name must be kebab-case`);
    const o = readOwner(d.name);
    if (o) list.push(o);
  }
  list.sort((a, b) => a.id.localeCompare(b.id));
  // Owner memory never overlaps: a shared or nested folder would load one owner's facts for another.
  for (let i = 0; i < list.length; i += 1) {
    for (let j = i + 1; j < list.length; j += 1) {
      const a = real(memoryDir(list[i])), b = real(memoryDir(list[j]));
      if (within(a, b) || within(b, a)) fail(1, `owners ${list[i].id} and ${list[j].id} share a memory folder (${a}, ${b}); give each its own`);
    }
  }
  return list;
}

function writeOwner(o) {
  const bad = problems(o, o.id);
  if (bad.length) fail(1, `refusing to write ${o.id}: ${bad.join('; ')}`);
  const dir = root(o.id);
  fs.mkdirSync(dir, { recursive: true });
  const f = path.join(dir, 'owner.json');
  const tmp = `${f}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(o, null, 2)}\n`);
  fs.renameSync(tmp, f);
}

function resolve(opts) {
  const owners = allOwners();
  if (opts.owner) {
    checkId(opts.owner);
    const o = owners.find((x) => x.id === opts.owner);
    if (!o) fail(4, `not found: ${opts.owner}${owners.length ? `; owners: ${owners.map((x) => x.id).join(' ')}` : ''}`);
    return { o, via: 'named' };
  }
  if (!owners.length) fail(4, 'none');
  if (owners.length === 1) return { o: owners[0], via: 'only' };
  const cwd = real(opts.cwd || process.cwd());
  let best = -1, hits = [];
  for (const o of owners) {
    for (const b of o.bindings || []) {
      const rb = real(b);
      if (!within(cwd, rb)) continue;
      const d = depth(rb);
      if (d > best) { best = d; hits = [{ o, b: rb }]; } else if (d === best) hits.push({ o, b: rb });
    }
  }
  const ids = [...new Set(hits.map((h) => h.o.id))];
  if (ids.length === 1) return { o: hits[0].o, via: `binding ${hits[0].b}` };
  const choices = ids.length ? ids : owners.map((x) => x.id);
  fail(3, `ambiguous: ${choices.join(' ')}\nname one with --owner <id>, or bind this folder: kaito-owner.mjs bind <id> <dir>`);
}

function printResolved({ o, via }) {
  console.log(`owner=${o.id}`);
  console.log(`root=${root(o.id)}`);
  console.log(`memory=${memoryDir(o)}`);
  console.log(`via=${via}`);
}

// Flags take a value; a flag given twice or without a value is a usage error.
function parse(argv, allowed) {
  const opts = {}, pos = [];
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const eq = a.indexOf('=');
      const k = (eq > 0 ? a.slice(2, eq) : a.slice(2));
      if (!allowed.includes(k)) fail(2, `unknown option --${k}\n${USAGE}`);
      if (k === 'json') { opts.json = true; continue; }
      const v = eq > 0 ? a.slice(eq + 1) : argv[(i += 1)];
      if (v === undefined || v === '' || (eq < 0 && v.startsWith('--'))) fail(2, `--${k} needs a value`);
      if (k in opts) fail(2, `--${k} given twice`);
      opts[k] = v;
    } else pos.push(a);
  }
  return { opts, pos };
}

function main(argv) {
  const [cmd, ...rest] = argv;
  switch (cmd) {
    case 'resolve': {
      const { opts, pos } = parse(rest, ['owner', 'cwd']);
      if (pos.length) fail(2, USAGE);
      return printResolved(resolve(opts));
    }
    case 'list': {
      const { opts, pos } = parse(rest, ['json']);
      if (pos.length) fail(2, USAGE);
      const owners = allOwners();
      if (opts.json) return console.log(JSON.stringify(owners.map((o) => ({ ...o, root: root(o.id), memory: memoryDir(o) })), null, 2));
      if (!owners.length) return console.log('none');
      for (const o of owners) console.log([o.id, o.kind, o.name, (o.bindings || []).join(',') || '-'].join('\t'));
      return undefined;
    }
    case 'add': {
      const { opts, pos } = parse(rest, ['name', 'kind', 'locale', 'timezone', 'currency', 'gstin']);
      if (pos.length !== 1 || !opts.name || !opts.kind) fail(2, 'usage: kaito-owner.mjs add <id> --name <name> --kind company|person [--locale <tag>] [--timezone <tz>] [--currency <ISO>] [--gstin <no>]');
      const id = checkId(pos[0]);
      allOwners(); // a broken record elsewhere is reported before anything is written
      if (fs.existsSync(path.join(root(id), 'owner.json'))) fail(1, `owner ${id} already exists: ${root(id)}`);
      const o = {
        id, name: opts.name, kind: opts.kind, locale: opts.locale || 'en-IN',
        timezone: opts.timezone || 'Asia/Kolkata', currency: opts.currency || 'INR',
        ...(opts.gstin ? { gstin: opts.gstin } : {}),
        bindings: [], channels: {}, keys: {}, cloud_ok: false,
      };
      writeOwner(o);
      fs.mkdirSync(memoryDir(o), { recursive: true });
      console.log(`added ${id}`);
      return printResolved({ o, via: 'named' });
    }
    case 'show': {
      const { opts, pos } = parse(rest, ['cwd']);
      if (pos.length > 1) fail(2, USAGE);
      const r = resolve({ owner: pos[0], cwd: opts.cwd });
      return console.log(JSON.stringify({ ...r.o, root: root(r.o.id), memory: memoryDir(r.o), via: r.via }, null, 2));
    }
    case 'bind': {
      const { pos } = parse(rest, []);
      if (pos.length !== 2) fail(2, 'usage: kaito-owner.mjs bind <id> <dir>');
      const id = checkId(pos[0]);
      const dir = real(pos[1]);
      let st;
      try { st = fs.statSync(dir); } catch { fail(4, `no such folder: ${dir}`); }
      if (!st.isDirectory()) fail(1, `not a folder: ${dir}`);
      const owners = allOwners();
      const o = owners.find((x) => x.id === id);
      if (!o) fail(4, `not found: ${id}`);
      const other = owners.find((x) => x.id !== id && (x.bindings || []).some((b) => real(b) === dir));
      if (other) fail(1, `${dir} is already bound to ${other.id}; run kaito-owner.mjs unbind ${dir} first`);
      if ((o.bindings || []).some((b) => real(b) === dir)) return console.log(`already bound: ${id} ${dir}`);
      o.bindings = [...(o.bindings || []), dir];
      writeOwner(o);
      return console.log(`bound: ${id} ${dir}`);
    }
    case 'unbind': {
      const { pos } = parse(rest, []);
      if (pos.length !== 1) fail(2, 'usage: kaito-owner.mjs unbind <dir>');
      const dir = real(pos[0]);
      let n = 0;
      for (const o of allOwners()) {
        const keep = (o.bindings || []).filter((b) => real(b) !== dir);
        if (keep.length === (o.bindings || []).length) continue;
        o.bindings = keep; writeOwner(o); n += 1;
        console.log(`unbound: ${o.id} ${dir}`);
      }
      if (!n) fail(4, `not bound: ${dir}`);
      return undefined;
    }
    default:
      fail(2, USAGE);
  }
  return undefined;
}

try {
  main(process.argv.slice(2));
} catch (e) {
  if (e instanceof Exit) {
    // An ambiguous or missing owner is an answer, not an error: it goes to stdout, the reason to stderr for the rest.
    if (e.code === 3 || (e.code === 4 && e.message === 'none')) console.log(e.message);
    else console.error(`kaito-owner: ${e.message}`);
    process.exit(e.code);
  }
  console.error(`kaito-owner: ${e.message}`);
  process.exit(1);
}
