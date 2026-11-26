// Shared code for kaito-ledger, kaito-approve and kaito-today. Node 22+ standard library only.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

// node:sqlite prints an ExperimentalWarning on Node 22 and 23. Drop only that one warning,
// then load the module (a static import would run before this filter is in place).
const emitWarning = process.emitWarning;
process.emitWarning = function (warning, ...rest) {
  const type = typeof rest[0] === 'string' ? rest[0] : rest[0]?.type ?? warning?.name;
  if (type === 'ExperimentalWarning' && /sqlite/i.test(String(warning?.message ?? warning))) return;
  return emitWarning.call(this, warning, ...rest);
};
let DatabaseSync;
try { ({ DatabaseSync } = await import('node:sqlite')); } catch {
  process.stderr.write(`kaito ledger needs Node 22.13 or newer (node:sqlite); this is ${process.version}\n`);
  process.exit(1);
}

export const EXIT = { ok: 0, error: 1, usage: 2, human: 3, notFound: 4 };
export const STATES = ['proposed', 'approved', 'claimed', 'sent', 'failed', 'uncertain', 'reconciled', 'rejected', 'expired'];
export const DEFAULT_TZ = 'Asia/Kolkata';
// An approved action may still be claimed this long after its due time; after that it expires.
export const LATE_LIMIT_MS = 24 * 3600 * 1000;
// A claim with no result after this long is listed by reconcile as stale.
export const STALE_CLAIM_MS = 30 * 60 * 1000;

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const MIGRATIONS_DIR = path.join(HERE, '..', 'migrations');

export class Fail extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
export const fail = (code, message) => { throw new Fail(code, message); };

// run(main): exit with the Fail code and print its message on stderr.
export async function run(main) {
  try {
    const code = await main(process.argv.slice(2));
    process.exitCode = code ?? EXIT.ok;
  } catch (e) {
    if (e instanceof Fail) {
      process.stderr.write(`${e.message}\n`);
      process.exitCode = e.code;
    } else {
      process.stderr.write(`error: ${e?.stack || e}\n`);
      process.exitCode = EXIT.error;
    }
  }
}

// parseArgs(argv, {multi: ['media'], bool: ['json']}): positionals plus --flags.
// A multi flag takes every value up to the next --flag and may repeat.
export function parseArgs(argv, { multi = [], bool = [] } = {}) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) { out._.push(a); continue; }
    let name = a.slice(2), value;
    const eq = name.indexOf('=');
    if (eq >= 0) { value = name.slice(eq + 1); name = name.slice(0, eq); }
    if (bool.includes(name)) {
      if (value !== undefined) fail(EXIT.usage, `--${name} takes no value`);
      out[name] = true; continue;
    }
    if (multi.includes(name)) {
      const list = out[name] ?? (out[name] = []);
      if (value !== undefined) { list.push(value); continue; }
      while (i + 1 < argv.length && !argv[i + 1].startsWith('--')) list.push(argv[++i]);
      if (!list.length) fail(EXIT.usage, `--${name} needs a value`);
      continue;
    }
    if (value === undefined) {
      if (i + 1 >= argv.length || argv[i + 1].startsWith('--')) fail(EXIT.usage, `--${name} needs a value`);
      value = argv[++i];
    }
    if (name in out) fail(EXIT.usage, `--${name} given twice`);
    out[name] = value;
  }
  return out;
}

export function only(args, allowed) {
  for (const k of Object.keys(args)) if (k !== '_' && !allowed.includes(k)) fail(EXIT.usage, `unknown flag --${k}`);
}

// ---------- paths ----------
export const kaitoHome = () => process.env.KAITO_HOME || path.join(os.homedir(), '.kaito');
export const businessDir = () => path.join(kaitoHome(), 'business');
export const dbPath = () => path.join(businessDir(), 'ledger.db');
export const artifactsDir = () => path.join(businessDir(), 'artifacts');
export const artifactPath = (sha) => path.join(artifactsDir(), sha.slice(0, 2), sha);

const OWNER_ID = /^[a-z0-9]+(-[a-z0-9]+)*$/;
export function checkOwnerId(id) {
  if (!id || !OWNER_ID.test(id) || id.length > 64) fail(EXIT.usage, `bad owner id: ${id ?? '(none)'}`);
  return id;
}

// readOwner(id): owner.json or null. A broken file is an error, not a missing owner.
export function readOwner(id) {
  checkOwnerId(id);
  const f = path.join(kaitoHome(), 'owners', id, 'owner.json');
  let text;
  try { text = fs.readFileSync(f, 'utf8'); } catch (e) { if (e.code === 'ENOENT') return null; throw e; }
  try { return JSON.parse(text); } catch { fail(EXIT.error, `owner.json is not valid JSON: ${f}`); }
}

export function ownerTz(id) {
  const o = id ? readOwner(id) : null;
  const tz = (o && typeof o.timezone === 'string' && o.timezone) || DEFAULT_TZ;
  checkTz(tz);
  return tz;
}

// ---------- hashing ----------
export const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
export const isSha = (s) => typeof s === 'string' && /^[0-9a-f]{64}$/.test(s);

// canonicalJson: sorted keys, no spaces, so the same payload always gives the same bytes.
export function canonicalJson(v) {
  if (v === null || typeof v !== 'object') {
    if (typeof v === 'number' && !Number.isSafeInteger(v)) fail(EXIT.error, 'canonical JSON takes integers only');
    return JSON.stringify(v);
  }
  if (Array.isArray(v)) return `[${v.map(canonicalJson).join(',')}]`;
  return `{${Object.keys(v).sort().filter((k) => v[k] !== undefined).map((k) => `${JSON.stringify(k)}:${canonicalJson(v[k])}`).join(',')}}`;
}

// canonicalText: the exact bytes that are stored, approved and sent. Valid UTF-8, no BOM, LF line ends.
export function canonicalText(buf) {
  let s;
  try { s = new TextDecoder('utf-8', { fatal: true }).decode(buf); } catch { fail(EXIT.usage, 'text file is not valid UTF-8'); }
  if (s.charCodeAt(0) === 0xfeff) s = s.slice(1);
  s = s.replace(/\r\n?/g, '\n');
  return Buffer.from(s, 'utf8');
}

// payloadOf(row, text, media): the object the digest covers. text and media are {sha256, bytes}.
export function payloadOf({ ref, owner, account, action, disclosure, due_at }, text, media) {
  return { v: 1, ref, owner, account, action, text: text ?? null, media, disclosure, due_at: due_at ?? null };
}
export const digestOf = (payload) => sha256(canonicalJson(payload));

// ---------- artifact store ----------
// putArtifact(buf): write once to artifacts/<aa>/<sha>, read-only, atomically. Returns the sha.
// A file already there under that name is kept if it hashes right; a damaged one is moved aside.
export function putArtifact(buf) {
  const sha = sha256(buf);
  const dest = artifactPath(sha);
  fs.mkdirSync(path.dirname(dest), { recursive: true, mode: 0o700 });
  if (fs.existsSync(dest)) {
    if (sha256(fs.readFileSync(dest)) === sha) return sha;
    fs.renameSync(dest, `${dest}.damaged-${Date.now()}`);
  }
  const tmp = `${dest}.tmp-${process.pid}-${crypto.randomBytes(4).toString('hex')}`;
  try {
    const fd = fs.openSync(tmp, 'wx', 0o600);
    try {
      for (let off = 0; off < buf.length;) off += fs.writeSync(fd, buf, off, buf.length - off);
      fs.fsyncSync(fd);
    } finally { fs.closeSync(fd); }
    if (sha256(fs.readFileSync(tmp)) !== sha) fail(EXIT.error, `artifact write did not land intact: ${dest}`);
    fs.chmodSync(tmp, 0o444);
    try {
      fs.linkSync(tmp, dest);  // fails if another writer got there first; then theirs must match
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      if (sha256(fs.readFileSync(dest)) !== sha) fail(EXIT.error, `artifact store is damaged: ${dest}`);
    }
  } finally { fs.rmSync(tmp, { force: true }); }
  return sha;
}

// readVerified(sha): the stored bytes, read once and checked against their name. A publisher
// sends this buffer, never a second read of the path.
export function readVerified(sha) {
  if (!isSha(sha)) fail(EXIT.usage, `bad sha256: ${sha}`);
  let buf;
  try { buf = fs.readFileSync(artifactPath(sha)); } catch { fail(EXIT.human, `stored file is missing: ${sha}`); }
  if (sha256(buf) !== sha) fail(EXIT.human, `stored file changed: ${sha}`);
  return buf;
}

// rehash(sha): the sha256 of the stored file now, or null when it is gone.
export function rehash(sha) {
  try { return sha256(fs.readFileSync(artifactPath(sha))); } catch (e) { if (e.code === 'ENOENT') return null; throw e; }
}

// ---------- time ----------
export function checkTz(tz) {
  try { new Intl.DateTimeFormat('en-US', { timeZone: tz }); } catch { fail(EXIT.usage, `unknown timezone: ${tz}`); }
}

// localParts(ms, tz): {y, m, d, hh, mm, ss, date: 'YYYY-MM-DD', time: 'HH:MM'} in that zone.
export function localParts(ms, tz) {
  const f = new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' });
  const p = Object.fromEntries(f.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  const r = { y: +p.year, m: +p.month, d: +p.day, hh: +p.hour, mm: +p.minute, ss: +p.second };
  r.date = `${p.year}-${p.month}-${p.day}`;
  r.time = `${p.hour}:${p.minute}`;
  return r;
}

// zonedToUtc(y, m, d, hh, mm, ss, tz): the UTC ms of that wall-clock time in tz.
export function zonedToUtc(y, m, d, hh, mm, ss, tz) {
  const want = Date.UTC(y, m - 1, d, hh, mm, ss);
  let t = want;
  for (let i = 0; i < 3; i++) {
    const p = localParts(t, tz);
    const diff = want - Date.UTC(p.y, p.m - 1, p.d, p.hh, p.mm, p.ss);
    if (diff === 0) break;
    t += diff;
  }
  return t;
}

export const isoUtc = (ms) => new Date(Math.floor(ms / 1000) * 1000).toISOString().replace('.000Z', 'Z');

// parseWhen(s, tz): {ms, allDay, date}. Accepts YYYY-MM-DD (a whole day in tz), a time with Z
// or an offset, or a time without one (read as tz wall-clock time). Impossible dates, times
// skipped by a clock change and times a clock change repeats are refused, never shifted.
export function parseWhen(s, tz) {
  if (typeof s !== 'string') fail(EXIT.usage, 'missing date');
  let m = s.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (m) {
    checkFields(+m[1], +m[2], +m[3], 0, 0, 0, s);
    return { ms: zonedToUtc(+m[1], +m[2], +m[3], 0, 0, 0, tz), allDay: true, date: s };
  }
  m = s.match(/^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?(Z|[+-]\d{2}:?\d{2})?$/);
  if (!m) fail(EXIT.usage, `bad date: ${s} (use YYYY-MM-DD or YYYY-MM-DDTHH:MM[:SS][Z|+05:30])`);
  const [y, mo, d, hh, mi, ss] = [m[1], m[2], m[3], m[4], m[5], m[6] ?? '0'].map(Number);
  const off = m[7];
  checkFields(y, mo, d, hh, mi, ss, s);
  if (off) {
    const om = off === 'Z' ? null : off.match(/^([+-])(\d{2}):?(\d{2})$/);
    const offMin = om ? (om[1] === '-' ? -1 : 1) * (+om[2] * 60 + +om[3]) : 0;
    if (om && (+om[2] > 14 || +om[3] > 59)) fail(EXIT.usage, `bad offset: ${s}`);
    return { ms: Date.UTC(y, mo - 1, d, hh, mi, ss) - offMin * 60000, allDay: false };
  }
  const ms = zonedToUtc(y, mo, d, hh, mi, ss, tz);
  const same = (t) => { const p = localParts(t, tz); return p.y === y && p.m === mo && p.d === d && p.hh === hh && p.mm === mi && p.ss === ss; };
  if (!same(ms)) fail(EXIT.usage, `${s} does not exist in ${tz} (a clock change skips it); give an offset`);
  if (same(ms - 3600000) || same(ms + 3600000)) fail(EXIT.usage, `${s} happens twice in ${tz} (a clock change repeats it); give an offset`);
  return { ms, allDay: false };
}
function checkFields(y, mo, d, hh, mi, ss, s) {
  const t = new Date(Date.UTC(y, mo - 1, d));
  if (y < 1970 || y > 9999 || t.getUTCMonth() !== mo - 1 || t.getUTCDate() !== d || hh > 23 || mi > 59 || ss > 59) fail(EXIT.usage, `bad date: ${s}`);
}

// now(args): --now <ISO> for tests and dry runs, else the clock.
export function nowMs(args) {
  if (!args?.now) return Date.now();
  const ms = Date.parse(args.now);
  if (Number.isNaN(ms) || !/(Z|[+-]\d{2}:?\d{2})$/.test(args.now)) fail(EXIT.usage, `--now needs a time with Z or an offset: ${args.now}`);
  return ms;
}

// ---------- database ----------
// openDb(): the ledger, migrated to the newest schema.
export function openDb() {
  fs.mkdirSync(businessDir(), { recursive: true, mode: 0o700 });
  const file = dbPath();
  const fresh = !fs.existsSync(file);
  const db = new DatabaseSync(file);
  if (fresh) { try { fs.chmodSync(file, 0o600); } catch { /* not ours to fix */ } }
  db.exec('PRAGMA busy_timeout = 10000');
  db.exec('PRAGMA journal_mode = WAL');
  db.exec('PRAGMA foreign_keys = ON');
  migrate(db);
  return db;
}

export function listMigrations(dir = MIGRATIONS_DIR) {
  let names;
  try { names = fs.readdirSync(dir); } catch (e) { if (e.code === 'ENOENT') return []; throw e; }
  const out = [];
  const seen = new Set();
  for (const n of names.sort()) {
    const m = n.match(/^(\d{3})-([a-z0-9-]+)\.sql$/);
    if (!m) continue;
    const version = +m[1];
    if (seen.has(version)) fail(EXIT.error, `two migrations share number ${m[1]} in ${dir}`);
    seen.add(version);
    const sql = fs.readFileSync(path.join(dir, n), 'utf8');
    out.push({ version, name: m[2], file: n, sql, sha256: sha256(sql) });
  }
  return out;
}

// migrate(db): apply each migration not yet recorded, in number order, one transaction each.
// A recorded migration whose file changed stops everything: migrations are append-only.
export function migrate(db) {
  db.exec('CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY, name TEXT NOT NULL, sha256 TEXT NOT NULL, applied_at TEXT NOT NULL)');
  const applied = [];
  for (const m of listMigrations()) {
    const have = db.prepare('SELECT sha256 FROM schema_version WHERE version = ?').get(m.version);
    if (have) {
      if (have.sha256 !== m.sha256) fail(EXIT.error, `migration ${m.file} changed after it was applied; add a new numbered file instead`);
      continue;
    }
    db.exec('BEGIN IMMEDIATE');
    try {
      // Another process may have applied it while we waited for the lock.
      if (!db.prepare('SELECT 1 FROM schema_version WHERE version = ?').get(m.version)) {
        db.exec(m.sql);
        db.prepare('INSERT INTO schema_version (version, name, sha256, applied_at) VALUES (?, ?, ?, ?)').run(m.version, m.name, m.sha256, isoUtc(Date.now()));
        applied.push(m.file);
      }
      db.exec('COMMIT');
    } catch (e) {
      try { db.exec('ROLLBACK'); } catch { /* already rolled back */ }
      throw e;
    }
  }
  return applied;
}

// tx(db, fn): fn inside BEGIN IMMEDIATE, so two writers never interleave.
export function tx(db, fn) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const r = fn();
    db.exec('COMMIT');
    return r;
  } catch (e) {
    try { db.exec('ROLLBACK'); } catch { /* already rolled back */ }
    throw e;
  }
}

export function event(db, ref, kind, detail) {
  db.prepare('INSERT INTO events (ref, at, kind, detail) VALUES (?, ?, ?, ?)').run(ref ?? null, isoUtc(Date.now()), kind, detail == null ? null : (typeof detail === 'string' ? detail : JSON.stringify(detail)));
}

export function getAction(db, ref) {
  if (!ref || !/^act-[0-9]{8}-[0-9a-f]{8}$/.test(ref)) fail(EXIT.usage, `bad ref: ${ref ?? '(none)'}`);
  const row = db.prepare('SELECT * FROM actions WHERE ref = ?').get(ref);
  if (!row) fail(EXIT.notFound, `not found: ${ref}`);
  return row;
}

// verifyAction(row): rebuild the payload from the row and the stored files as they are now.
// Returns {digest, payload, problems}: problems lists every file that is gone or changed.
export function verifyAction(row) {
  const problems = [];
  const check = (sha, label) => {
    const now = rehash(sha);
    if (now === null) problems.push(`${label} file is missing from the artifact store`);
    else if (now !== sha) problems.push(`${label} file changed after it was stored`);
    const bytes = now === null ? 0 : fs.statSync(artifactPath(sha)).size;
    return { sha256: now ?? 'missing', bytes };
  };
  const text = row.text_sha256 ? check(row.text_sha256, 'text') : null;
  const media = JSON.parse(row.media_json).map((sha, i) => check(sha, `media ${i + 1}`));
  const payload = payloadOf(row, text, media);
  const digest = digestOf(payload);
  if (digest !== row.digest && !problems.length) problems.push('the action row no longer matches its digest (owner, account, action, disclosure or due time changed)');
  return { digest, payload, problems };
}

// tooLate(row, ms): past due by more than the late limit.
export const tooLate = (row, ms) => row.due_at != null && ms > Date.parse(row.due_at) + LATE_LIMIT_MS;

export function printKv(obj) {
  for (const [k, v] of Object.entries(obj)) {
    if (Array.isArray(v)) for (const x of v) process.stdout.write(`${k}=${x}\n`);
    else if (v !== undefined && v !== null) process.stdout.write(`${k}=${v}\n`);
  }
}
