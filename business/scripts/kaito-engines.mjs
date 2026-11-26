#!/usr/bin/env node
// kaito-engines: engine registry, doctor, pick and cloud consent. Node 22 standard library only.
// Usage:
//   kaito-engines.mjs doctor [--json] [--capability c] [--owner id]
//   kaito-engines.mjs pick <capability> [--owner id] [--allow-cloud] [--force] [--json]
//   kaito-engines.mjs consent <provider> --owner id [--grant|--revoke|--status]
//   kaito-engines.mjs enable|disable <provider>
// Exit codes: 0 ok, 1 error, 2 usage, 3 needs a human decision, 4 not found.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REGISTRY = path.join(HERE, '..', 'engines', 'registry.json');
const OWNER_RE = /^[a-z0-9][a-z0-9-]*$/;
const GB = 1024 ** 3;

const kaitoHome = () => process.env.KAITO_HOME || path.join(os.homedir(), '.kaito');
const expand = (p) => (p === '~' ? os.homedir() : p.startsWith('~/') ? path.join(os.homedir(), p.slice(2)) : p);

class Usage extends Error {}
const die = (code, msg) => { process.stderr.write(msg + '\n'); process.exit(code); };

// ---------- registry and overrides ----------

function readJson(file, what) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (e) {
    if (e.code === 'ENOENT') return null;
    die(1, `${what} is not valid JSON: ${file}`);
  }
}

// Merge rules are documented in business/references/engines.md.
function loadConfig() {
  const reg = readJson(REGISTRY, 'registry');
  if (!reg) die(1, `registry missing: ${REGISTRY}`);
  const ovFile = path.join(kaitoHome(), 'engines.json');
  const ov = readJson(ovFile, 'engines.json') || {};
  const warnings = [];
  const providers = {};
  for (const [id, def] of Object.entries(reg.providers)) providers[id] = { id, enabled: true, heavy: false, ...structuredClone(def) };
  const own = (o, k) => Object.hasOwn(o, k);
  for (const [id, o] of Object.entries(ov.providers || {})) {
    if (!o || typeof o !== 'object') { warnings.push(`engines.json: provider ${id} ignored (not an object)`); continue; }
    const { license, path: p, paths, id: _id, kind: _kind, ...rest } = o;
    const override = p || (Array.isArray(paths) ? paths[0] : undefined);
    if (!own(providers, id)) {
      const okChecks = Array.isArray(o.checks) && o.checks.length > 0;
      if (!OWNER_RE.test(id) || !['local', 'cloud'].includes(o.kind) || !(okChecks || (o.key && typeof o.key.pattern === 'string'))) { warnings.push(`engines.json: new provider ${id} needs kind and a non-empty checks list or key; ignored`); continue; }
      const lic = { id: 'unknown', commercial: false, ...(license || {}) };
      providers[id] = { min_ram_gb: 0, disk_gb: 0, heavy: false, ...structuredClone(rest), id, kind: o.kind, license: lic, enabled: o.enabled === undefined ? lic.commercial === true : o.enabled };
      if (override) providers[id].override_path = override;
      continue;
    }
    if (rest.checks !== undefined && !(Array.isArray(rest.checks) && rest.checks.length)) { warnings.push(`engines.json: checks for ${id} ignored (not a non-empty list)`); delete rest.checks; }
    Object.assign(providers[id], structuredClone(rest));
    if (license) providers[id].license = { ...providers[id].license, ...license };
    if (override) providers[id].override_path = override;
  }
  const capabilities = {};
  for (const [cap, ids] of Object.entries(reg.capabilities)) capabilities[cap] = [...ids];
  for (const [cap, ids] of Object.entries(ov.capabilities || {})) {
    if (!Array.isArray(ids)) { warnings.push(`engines.json: capability ${cap} ignored (not a list)`); continue; }
    const known = ids.filter((i) => own(providers, i) || (warnings.push(`engines.json: ${cap} names unknown provider ${i}`), false));
    const rest = (own(capabilities, cap) ? capabilities[cap] : []).filter((i) => !known.includes(i));
    capabilities[cap] = [...new Set([...known, ...rest])];
  }
  return { providers, capabilities, warnings, ovFile };
}

// ---------- low level checks ----------

function isExec(p) {
  try { return fs.statSync(p).isFile() && (fs.accessSync(p, fs.constants.X_OK), true); } catch { return false; }
}
function exists(p) { try { fs.statSync(p); return true; } catch { return false; } }

// Expand "*" per path segment. No other glob syntax.
function globPath(pattern) {
  const p = expand(pattern);
  if (!p.includes('*')) return [p];
  const parts = p.split(path.sep);
  let cur = [parts[0] === '' ? path.sep : parts[0]];
  for (const seg of parts.slice(1)) {
    const next = [];
    for (const base of cur) {
      if (!seg.includes('*')) { next.push(path.join(base, seg)); continue; }
      const re = new RegExp('^' + seg.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$');
      let names = [];
      try { names = fs.readdirSync(base).filter((n) => re.test(n)).sort(); } catch { /* none */ }
      for (const n of names) next.push(path.join(base, n));
    }
    cur = next;
  }
  return cur;
}

function onPath(name) {
  for (const d of (process.env.PATH || '').split(path.delimiter)) {
    if (d && isExec(path.join(d, name))) return path.join(d, name);
  }
  return null;
}

function run(file, args, timeout) {
  return new Promise((resolve) => {
    execFile(file, args, { timeout, encoding: 'utf8', maxBuffer: 1 << 20 }, (err, stdout, stderr) => resolve({ ok: !err, out: (stdout || stderr || '').trim() }));
  });
}

// Find the check an override replaces: the first bin, path or python check, or the http check for a URL.
function overrideTarget(checks, isUrl) {
  for (const c of checks) {
    if (c.any) { const t = overrideTarget(c.any, isUrl); if (t) return t; continue; }
    if (isUrl ? c.type === 'http' : ['bin', 'path', 'python'].includes(c.type)) return c;
  }
  return null;
}

function prepare(p) {
  const checks = structuredClone(p.checks || []);
  const key = p.key ? structuredClone(p.key) : null;
  const value = (p.env && process.env[p.env]) || p.override_path || null;
  let overridden = false;
  if (value) {
    if (key) { key.pattern = value; overridden = true; }
    else {
      const isUrl = /^https?:\/\//.test(value);
      const t = overrideTarget(checks, isUrl);
      if (t) {
        overridden = true;
        if (isUrl) {
          t.url = value;
          for (const c of checks) if (c.any && c.any.includes(t)) c.any = [t];  // an explicit URL is the only place to look
        } else { t.paths = [value]; t.names = []; }
      }
    }
  }
  return { checks, key, overridden, value };
}

const hfCache = () => process.env.HF_HUB_CACHE || (process.env.HF_HOME ? path.join(process.env.HF_HOME, 'hub') : path.join(os.homedir(), '.cache', 'huggingface', 'hub'));

let dockerImages;
async function dockerHas(image) {
  if (!dockerImages) {
    dockerImages = (async () => {
      const bin = process.env.DOCKER_BIN || onPath('docker') || ['~/.docker/bin/docker', '/usr/local/bin/docker', '/opt/homebrew/bin/docker'].map(expand).find(isExec);
      if (!bin) return null;
      const r = await run(bin, ['image', 'ls', '--format', '{{.Repository}}'], 6000);
      return r.ok ? new Set(r.out.split('\n').filter(Boolean)) : null;
    })();
  }
  const set = await dockerImages;
  return !!set && set.has(image);
}

async function probe(url) {
  try { await fetch(url, { signal: AbortSignal.timeout(1500), redirect: 'manual' }); return true; } catch { return false; }
}

function postizEndpoint(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('invalid Postiz URL'); }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) {
    throw new Error('invalid Postiz URL');
  }
  const remote = !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
  if (remote && url.protocol !== 'https:') throw new Error('remote Postiz requires HTTPS');
  return { endpoint: url.origin + url.pathname.replace(/\/+$/, ''), origin: url.origin, remote };
}

async function postizCheck(value, probePath = '') {
  let target;
  try { target = postizEndpoint(value); }
  catch (error) { return { ok: false, detail: error.message }; }
  // The handler checks remote availability on its first authenticated request after consent.
  if (target.remote || await probe(target.endpoint + probePath)) {
    return { ok: true, resolved: target.endpoint, ...target };
  }
  return { ok: false, detail: `no answer on ${target.endpoint}` };
}

// Returns {ok, resolved, version, detail}.
async function runCheck(c, postiz) {
  if (c.any) {
    const rs = [];
    for (const sub of c.any) { const r = await runCheck(sub, postiz); if (r.ok) return r; rs.push(r.detail); }
    return { ok: false, detail: rs.join('; ') };
  }
  switch (c.type) {
    case 'always': return { ok: true, resolved: 'host' };
    case 'bin': {
      const cands = [];
      for (const n of c.names || []) { const f = n.includes('/') ? expand(n) : onPath(n); if (f) cands.push(f); }
      for (const g of c.paths || []) cands.push(...globPath(g));
      const found = cands.find(isExec);
      if (!found) return { ok: false, detail: `not found: ${(c.names || []).join('/') || (c.paths || [])[0] || 'path'}` };
      let version;
      if (c.version) { const r = await run(found, c.version, 3000); if (r.ok) version = r.out.split('\n')[0].slice(0, 80); }
      return { ok: true, resolved: found, version };
    }
    case 'path': {
      const found = (c.paths || []).flatMap(globPath).find(exists);
      return found ? { ok: true, resolved: found } : { ok: false, detail: `not found: ${(c.paths || [])[0]}` };
    }
    case 'python': {
      const cands = (c.paths || []).flatMap((p) => (p.includes('/') ? globPath(p) : [onPath(p)])).filter(Boolean);
      const py = cands.find(isExec);
      if (!py) return { ok: false, detail: `python not found: ${(c.paths || [])[0]}` };
      if (c.module) {
        const r = await run(py, ['-I', '-c', `import ${c.module}`], 10000);
        if (!r.ok) return { ok: false, detail: `python module ${c.module} missing` };
      }
      return { ok: true, resolved: py };
    }
    case 'hf': {
      const out = [];
      for (const m of c.models || []) {
        const dir = path.join(hfCache(), 'models--' + m.replace(/\//g, '--'), 'snapshots');
        let snaps = [];
        try { snaps = fs.readdirSync(dir).filter((n) => !n.startsWith('.') && fs.readdirSync(path.join(dir, n)).length > 0); } catch { /* none */ }
        if (!snaps.length) return { ok: false, detail: `model not in cache: ${m}` };
        out.push(path.join(dir, snaps[0]));
      }
      return { ok: true, resolved: out[0] };
    }
    case 'http': {
      const urls = c.url ? [c.url] : (c.ports || []).map((p) => `http://127.0.0.1:${p}`);
      if (postiz) {
        const results = [];
        for (const u of urls) {
          const result = await postizCheck(u, c.url ? '' : c.path || '/');
          if (result.ok) return result;
          results.push(result.detail);
        }
        return { ok: false, detail: results.join('; ') };
      }
      for (const u of urls) if (await probe(u.replace(/\/$/, '') + (c.url ? '' : c.path || '/'))) return { ok: true, resolved: redactUrl(u), remote: !isLoopback(u) };
      return { ok: false, detail: `no answer on ${urls.map((u) => redactUrl(u).replace(/^https?:\/\//, '')).join(', ')}` };
    }
    case 'docker':
      return (await dockerHas(c.image)) ? { ok: true, resolved: `docker:${c.image}` } : { ok: false, detail: `docker image missing: ${c.image}` };
    default: return { ok: false, detail: `unknown check type ${c.type}` };
  }
}

// Never print credentials or query strings that ride in a service URL.
function redactUrl(u) {
  try { const x = new URL(u); x.username = ''; x.password = ''; x.search = ''; x.hash = ''; return x.toString().replace(/\/$/, ''); } catch { return 'invalid-url'; }
}
const isLoopback = (u) => { try { return ['127.0.0.1', 'localhost', '[::1]'].includes(new URL(u).hostname); } catch { return false; } };

function keyStatus(key, owner) {
  const pat = expand(key.pattern);
  if (owner) {
    const file = pat.replace('<owner>', owner);
    let ok = false; try { ok = fs.statSync(file).isFile(); } catch { /* missing */ }
    return { pattern: key.pattern, file, present: ok };
  }
  if (!pat.includes('<owner>')) { let ok = false; try { ok = fs.statSync(pat).isFile(); } catch { /* missing */ } return { pattern: key.pattern, file: pat, present: ok }; }
  const dir = path.dirname(pat), [pre, post] = path.basename(pat).split('<owner>');
  let names = [];
  try { names = fs.readdirSync(dir).filter((n) => n.startsWith(pre) && n.endsWith(post) && n.length > pre.length + post.length && fs.statSync(path.join(dir, n)).isFile()); } catch { /* none */ }
  return { pattern: key.pattern, file: names.length ? path.join(dir, names[0]) : null, present: names.length > 0, count: names.length };
}

// ---------- memory and disk ----------

function memory() {
  const t = process.env.KAITO_TEST_MEM_GB;   // tests only
  const f = process.env.KAITO_TEST_FREE_GB;  // tests only
  const num = (v) => (v !== undefined && v !== '' && Number.isFinite(Number(v)) ? Number(v) : null);
  const total = num(t) ?? os.totalmem() / GB;
  if (num(f) !== null) return { total, avail: num(f), source: 'KAITO_TEST_FREE_GB' };
  let avail = os.freemem() / GB, source = 'os.freemem';
  try {
    if (process.platform === 'darwin') {
      const out = readVmStat();
      if (out) { avail = out; source = 'vm_stat free+inactive+purgeable+speculative'; }
    } else if (process.platform === 'linux') {
      const m = /MemAvailable:\s+(\d+) kB/.exec(fs.readFileSync('/proc/meminfo', 'utf8'));
      if (m) { avail = Number(m[1]) * 1024 / GB; source = 'MemAvailable'; }
    }
  } catch { /* keep the fallback */ }
  return { total, avail: num(t) !== null ? Math.min(avail, total) : avail, source };
}
function readVmStat() {
  const out = execFileSync('vm_stat', { encoding: 'utf8', timeout: 3000 });
  const size = Number(/page size of (\d+) bytes/.exec(out)?.[1] || 16384);
  const n = (label) => Number(new RegExp(`Pages ${label}:\\s+(\\d+)`).exec(out)?.[1] || 0);
  return (n('free') + n('inactive') + n('purgeable') + n('speculative')) * size / GB;
}
function diskFreeGB() { try { const s = fs.statfsSync(os.homedir()); return s.bavail * s.bsize / GB; } catch { return null; } }

// ---------- evaluate ----------

async function evaluate(p, owner) {
  const prep = prepare(p);
  const results = [];
  if (p.id === 'postiz' && prep.value) results.push(await postizCheck(prep.value));
  else for (const c of prep.checks) results.push(await runCheck(c, p.id === 'postiz'));
  const key = prep.key ? keyStatus(prep.key, owner) : null;
  const checksOk = results.every((r) => r.ok);
  const present = checksOk && (!key || key.present);
  const reasons = results.filter((r) => !r.ok).map((r) => r.detail);
  if (key && !key.present) reasons.push(`key file missing: ${key.pattern.replace('<owner>', owner || '<owner>')}`);
  const first = results.find((r) => r.ok && r.resolved);
  return {
    endpoint: first?.endpoint, origin: first?.origin,
    id: p.id, name: p.name, kind: results.some((r) => r.remote) ? 'cloud' : p.kind, remote_url: results.some((r) => r.remote) || undefined, enabled: p.enabled !== false, heavy: !!p.heavy,
    present, resolved: key ? (owner ? key.file : key.present ? key.pattern : undefined) : first?.resolved, version: results.map((r) => r.version).find(Boolean),
    key: key ? { pattern: key.pattern, present: key.present, file: owner ? key.file || undefined : undefined, count: key.count } : undefined,
    env: p.env, overridden: prep.overridden, min_ram_gb: p.min_ram_gb || 0, disk_gb: p.disk_gb || 0,
    license: p.license?.id, commercial: !!p.license?.commercial, license_note: p.license?.note,
    source: p.source, reasons: present ? [] : reasons,
  };
}

// ---------- consent ----------

function consentFile(owner) { return path.join(kaitoHome(), 'owners', owner, 'consent.json'); }
function readConsent(owner) {
  const j = readJson(consentFile(owner), 'consent.json');
  return j && j.cloud && typeof j.cloud === 'object' ? j : { version: 1, cloud: {} };
}
const hasConsent = (owner, id, origin) => {
  const c = readConsent(owner).cloud;
  return Object.hasOwn(c, id) && c[id]?.granted === true && (id !== 'postiz' || (typeof origin === 'string' && c[id].origin === origin));
};
function writeAtomic(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + '\n', { mode: 0o600 });
  fs.renameSync(tmp, file);
}

// Serialise consent read-modify-write per owner.
async function lock(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  for (let i = 0; i < 100; i++) {
    try { const fd = fs.openSync(file, 'wx'); fs.closeSync(fd); return () => { try { fs.unlinkSync(file); } catch { /* gone */ } }; }
    catch (e) {
      if (e.code !== 'EEXIST') throw e;
      try { if (Date.now() - fs.statSync(file).mtimeMs > 10000) fs.unlinkSync(file); } catch { /* raced */ }
      await new Promise((r) => setTimeout(r, 50));
    }
  }
  throw new Error(`could not lock ${file}`);
}

// ---------- decide ----------

// Walks a capability's providers in order. Returns {pick} or {blockers, notes}.
function decide(cfg, evals, cap, { owner, allowCloud, force }) {
  const ids = cfg.capabilities[cap];
  const notes = [], blockers = [];
  const mem = memory();
  for (const id of ids) {
    const e = evals[id];
    if (!e.enabled) { notes.push(`${id}: disabled${e.commercial ? '' : ' (non-commercial license, opt in with: kaito-engines enable ' + id + ')'}`); continue; }
    if (!e.present) { notes.push(`${id}: missing (${e.reasons.join('; ') || 'not installed'})`); continue; }
    if (e.kind === 'cloud') {
      if (!allowCloud) { notes.push(`${id}: cloud, skipped without --allow-cloud`); continue; }
      if (!owner) { blockers.push(`${id}: cloud needs --owner <id> to check consent`); continue; }
      if (!hasConsent(owner, id, e.origin)) { blockers.push(`${id}: no cloud-upload consent for owner ${owner}. Ask the owner, then run: kaito-engines consent ${id} --owner ${owner} --grant`); continue; }
    } else if (e.heavy && !force) {
      if (mem.total < e.min_ram_gb) { blockers.push(`${id}: needs ${e.min_ram_gb} GB RAM, this machine has ${mem.total.toFixed(0)} GB. Use --force to override`); continue; }
      if (mem.avail < e.min_ram_gb) { blockers.push(`${id}: needs ${e.min_ram_gb} GB RAM, only ${mem.avail.toFixed(1)} GB free or reclaimable (it would swap). Close other heavy models or use --force`); continue; }
    }
    return { pick: e, notes };
  }
  return { blockers, notes };
}

// ---------- commands ----------

function parseArgs(argv) {
  const valued = new Set(['--owner', '--capability']);
  const bools = new Set(['--json', '--allow-cloud', '--force', '--grant', '--revoke', '--status']);
  const flags = {}, pos = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (valued.has(a)) { if (i + 1 >= argv.length) throw new Usage(`${a} needs a value`); flags[a.slice(2)] = argv[++i]; }
    else if (bools.has(a)) flags[a.slice(2)] = true;
    else if (a.startsWith('--')) throw new Usage(`unknown option ${a}`);
    else pos.push(a);
  }
  if (flags.owner && !OWNER_RE.test(flags.owner)) throw new Usage(`bad owner id: ${flags.owner}`);
  return { flags, pos };
}

async function evalAll(cfg, owner, only) {
  const ids = [...new Set(Object.entries(cfg.capabilities).filter(([c]) => !only || c === only).flatMap(([, l]) => l))];
  const evals = {};
  await Promise.all(ids.map(async (id) => { evals[id] = await evaluate(cfg.providers[id], owner); }));
  return evals;
}

const yn = (b) => (b ? 'yes' : 'no');

async function cmdDoctor(flags) {
  const cfg = loadConfig();
  if (flags.capability && !Object.hasOwn(cfg.capabilities, flags.capability)) throw new Usage(`unknown capability ${flags.capability}. Known: ${Object.keys(cfg.capabilities).join(' ')}`);
  const evals = await evalAll(cfg, flags.owner, flags.capability);
  const mem = memory(), disk = diskFreeGB();
  const caps = Object.keys(cfg.capabilities).filter((c) => !flags.capability || c === flags.capability);
  const summary = {};
  for (const cap of caps) {
    const r = decide(cfg, evals, cap, { owner: flags.owner, allowCloud: false });
    if (r.pick) summary[cap] = { status: 'ok', provider: r.pick.id, path: r.pick.resolved, kind: r.pick.kind, commercial: r.pick.commercial };
    else {
      const cloud = cfg.capabilities[cap].find((id) => evals[id].enabled && evals[id].present && evals[id].kind === 'cloud');
      const why = [...r.blockers, ...r.notes];
      summary[cap] = { status: r.blockers.length ? 'blocked' : 'none', provider: null, cloud_available: cloud || null, notes: why };
    }
  }
  if (flags.json) {
    const order = [...new Set(caps.flatMap((c) => cfg.capabilities[c]))];
    const providers = order.map((id) => ({ ...evals[id], capabilities: caps.filter((c) => cfg.capabilities[c].includes(id)) }));
    process.stdout.write(JSON.stringify({ machine: { total_ram_gb: +mem.total.toFixed(1), available_ram_gb: +mem.avail.toFixed(1), ram_source: mem.source, disk_free_gb: disk && +disk.toFixed(1) }, providers, summary, warnings: cfg.warnings }, null, 2) + '\n');
    return 0;
  }
  const out = [];
  out.push(`machine: ${mem.total.toFixed(0)} GB RAM, ${mem.avail.toFixed(1)} GB free or reclaimable, ${disk === null ? 'disk unknown' : disk.toFixed(0) + ' GB disk free'}`);
  for (const w of cfg.warnings) out.push(`warning: ${w}`);
  const seen = new Set();
  for (const cap of caps) for (const id of cfg.capabilities[cap]) {
    if (seen.has(id)) continue; seen.add(id);
    const e = evals[id];
    const st = !e.enabled ? (e.present ? 'off' : 'off,missing') : e.present ? 'present' : 'missing';
    const ram = e.min_ram_gb ? `ram ${e.min_ram_gb}/${mem.total.toFixed(0)}GB${mem.total < e.min_ram_gb ? ' TOO SMALL' : e.heavy && mem.avail < e.min_ram_gb ? ' (free ' + mem.avail.toFixed(0) + ')' : ''}` : 'ram -';
    const disk_ = e.disk_gb ? `disk ${e.disk_gb}GB` : 'disk -';
    const key = e.key ? `key:${e.key.present ? 'present' : 'missing'}` : 'key:-';
    const where = e.present ? [e.resolved, e.version].filter(Boolean).join('  ') : e.reasons[0] || '';
    out.push([st.padEnd(11), id.padEnd(20), e.kind.padEnd(5), ram.padEnd(22), disk_.padEnd(10), `${e.license} commercial:${yn(e.commercial)}`.padEnd(46), key.padEnd(12), where].join(' ').trimEnd());
  }
  out.push('');
  out.push('each capability will use:');
  for (const cap of caps) {
    const s = summary[cap];
    out.push(s.status === 'ok' ? `  ${cap.padEnd(18)} ${s.provider}${s.commercial ? '' : ' (non-commercial)'}`
      : `  ${cap.padEnd(18)} ${s.status}${s.cloud_available ? ` (cloud ${s.cloud_available} is present: needs --allow-cloud and consent)` : ''}${s.notes.length ? ': ' + s.notes.join('; ') : ''}`);
  }
  process.stdout.write(out.join('\n') + '\n');
  return 0;
}

async function cmdPick(pos, flags) {
  const cap = pos[0];
  if (!cap || pos.length > 1) throw new Usage('usage: pick <capability> [--owner id] [--allow-cloud] [--force] [--json]');
  const cfg = loadConfig();
  if (!Object.hasOwn(cfg.capabilities, cap)) throw new Usage(`unknown capability ${cap}. Known: ${Object.keys(cfg.capabilities).join(' ')}`);
  const evals = await evalAll(cfg, flags.owner, cap);
  const r = decide(cfg, evals, cap, { owner: flags.owner, allowCloud: !!flags['allow-cloud'], force: !!flags.force });
  if (r.pick) {
    const e = r.pick;
    if (!e.commercial) process.stderr.write(`warning: ${e.id} weights are ${e.license}, not cleared for commercial use. ${e.license_note || ''}\n`);
    if (flags.json) process.stdout.write(JSON.stringify({ capability: cap, provider: e.id, path: e.resolved, endpoint: e.endpoint, kind: e.kind, license: e.license, commercial: e.commercial, env: e.env, version: e.version }) + '\n');
    else process.stdout.write(`provider=${e.id}\npath=${e.resolved}\nkind=${e.kind}\nlicense=${e.license}\ncommercial=${yn(e.commercial)}\n`);
    return 0;
  }
  if (r.blockers.length) { process.stderr.write(r.blockers.join('\n') + '\n'); return 3; }
  process.stderr.write(`none usable for ${cap}\n${r.notes.join('\n')}\n`);
  return 4;
}

async function cmdConsent(pos, flags) {
  const id = pos[0];
  if (!id || pos.length > 1 || !flags.owner) throw new Usage('usage: consent <provider> --owner <id> [--grant|--revoke|--status]');
  const cfg = loadConfig();
  const p = Object.hasOwn(cfg.providers, id) ? cfg.providers[id] : null;
  if (!p) throw new Usage(`unknown provider ${id}`);
  if (p.kind !== 'cloud' && id !== 'postiz') throw new Usage(`${id} is local; consent applies to cloud providers only`);
  let origin;
  if (id === 'postiz' && !flags.revoke) {
    const endpoint = await evaluate(p, flags.owner);
    if (endpoint.kind !== 'cloud' || !endpoint.origin) throw new Usage('configure a remote Postiz HTTPS URL before managing its consent');
    origin = endpoint.origin;
  }
  const file = consentFile(flags.owner);
  if (flags.grant && flags.revoke) throw new Usage('choose --grant or --revoke');
  const unlock = (flags.grant || flags.revoke) ? await lock(file + '.lock') : () => {};
  try {
  const c = readConsent(flags.owner);
  if (flags.grant) {
    c.cloud[id] = { granted: true, at: new Date().toISOString(), ...(origin && { origin }) };
    writeAtomic(file, c);
    process.stdout.write(`granted: ${id} for ${flags.owner}\n`);
  } else if (flags.revoke) {
    c.cloud[id] = { granted: false, at: c.cloud[id]?.at, revoked_at: new Date().toISOString() };
    writeAtomic(file, c);
    process.stdout.write(`revoked: ${id} for ${flags.owner}\n`);
  } else {
    process.stdout.write(`${id} for ${flags.owner}: ${hasConsent(flags.owner, id, origin) ? 'granted' : 'not granted'}\n`);
  }
  } finally { unlock(); }
  return 0;
}

async function cmdToggle(on, pos) {
  const id = pos[0];
  if (!id || pos.length > 1) throw new Usage(`usage: ${on ? 'enable' : 'disable'} <provider>`);
  const cfg = loadConfig();
  if (!Object.hasOwn(cfg.providers, id)) throw new Usage(`unknown provider ${id}`);
  const j = readJson(cfg.ovFile, 'engines.json') || {};
  j.providers = j.providers || {};
  j.providers[id] = { ...j.providers[id], enabled: on };
  writeAtomic(cfg.ovFile, j);
  const p = cfg.providers[id];
  process.stdout.write(`${on ? 'enabled' : 'disabled'}: ${id}\n`);
  if (on && !p.license?.commercial) process.stderr.write(`warning: ${id} is ${p.license?.id}, not cleared for commercial use. ${p.license?.note || ''}\n`);
  return 0;
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  try {
    const { flags, pos } = parseArgs(rest);
    switch (cmd) {
      case 'doctor': return await cmdDoctor(flags);
      case 'pick': return await cmdPick(pos, flags);
      case 'consent': return await cmdConsent(pos, flags);
      case 'enable': return await cmdToggle(true, pos);
      case 'disable': return await cmdToggle(false, pos);
      default: throw new Usage('usage: kaito-engines.mjs doctor|pick|consent|enable|disable ...');
    }
  } catch (e) {
    if (e instanceof Usage) { process.stderr.write(e.message + '\n'); return 2; }
    process.stderr.write(`error: ${e.message}\n`); return 1;
  }
}

process.exit(await main());
