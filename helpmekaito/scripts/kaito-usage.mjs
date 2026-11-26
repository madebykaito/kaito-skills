// Token usage per day and model, read from the runners' own logs on this machine. No network calls.
//   node kaito-usage.mjs report [days]                  table for the last <days> days (default 7)
//   node kaito-usage.mjs consent check <runner> <model>  prints ask (pay-per-token, no yes today) or ok
//   node kaito-usage.mjs consent yes <model>             records today's yes under ~/.kaito
// KAITO_TODAY=YYYY-MM-DD replaces today's date (tests).
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, existsSync, openSync, readSync, closeSync, mkdtempSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir, tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { StringDecoder } from 'node:string_decoder';
import { fileURLToPath, pathToFileURL } from 'node:url';

const env = process.env;
const here = dirname(fileURLToPath(import.meta.url));
const home = env.HOME || homedir();
const kaitoHome = env.KAITO_HOME || join(home, '.kaito');
const pad = (n) => String(n).padStart(2, '0');
const dayOf = (t) => {  // local calendar day of a timestamp; '' for a bad one
  const d = new Date(t);
  return isNaN(d) ? '' : `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
// Calendar arithmetic on a YYYY-MM-DD day: no clock time involved, so DST and odd zones cannot shift it.
const shift = (day, n) => {
  const [y, m, d] = day.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n, 12)).toISOString().slice(0, 10);
};
const isDay = (s) => /^\d{4}-\d\d-\d\d$/.test(s || '') && shift(s, 0) === s;
const today = isDay(env.KAITO_TODAY) ? env.KAITO_TODAY : dayOf(Date.now());
const num = (v) => (Number.isFinite(v) && v > 0 ? v : 0);
const obj = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : {});
const json = (file) => { try { return JSON.parse(readFileSync(file, 'utf8')); } catch { return undefined; } };
// One line at a time, so a log of any size never has to fit in one string.
function* lines(file) {
  const fd = openSync(file, 'r'), buf = Buffer.alloc(1 << 16), dec = new StringDecoder('utf8');
  let rest = '';
  try {
    for (let n; (n = readSync(fd, buf, 0, buf.length, null)) > 0;) {
      const parts = (rest + dec.write(buf.subarray(0, n))).split('\n');
      rest = parts.pop();
      yield* parts;
    }
    if (rest) yield rest;
  } finally { closeSync(fd); }
}
const walk = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
  e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)]);
// Log files under the dirs that changed inside the window, oldest name first; older sessions are never opened.
const recent = (dirs, since, re) => dirs.filter(existsSync).flatMap(walk)
  .filter((f) => re.test(f) && statSync(f).mtimeMs >= since).sort();
// Runs fn on each file. A file that cannot be read or parsed is counted and skipped, never the whole runner.
const each = (files, fn) => files.reduce((bad, f) => { try { fn(f); return bad; } catch { return bad + 1; } }, 0);
const total = (r) => r.input + r.output + r.cacheRead + r.cacheWrite;

// ---- collectors: each returns { rows: [{ ts, model, input, output, cacheRead, cacheWrite, cacheWrite1h }], bad }
// or { error: reason }. input never includes cached tokens.

function claude(since) {
  const dir = join(env.CLAUDE_CONFIG_DIR || join(home, '.claude'), 'projects');
  if (!existsSync(dir)) return { error: `no session logs at ${dir}` };
  const seen = new Map();
  const bad = each(recent([dir], since, /\.jsonl$/), (f) => {
    for (const l of lines(f)) {
      if (!l.includes('"usage"')) continue;
      let o; try { o = obj(JSON.parse(l)); } catch { continue; }
      const m = obj(o.message), u = m.usage;
      if (!u || typeof u !== 'object' || !m.model || m.model === '<synthetic>') continue;
      const row = { ts: o.timestamp, model: m.model, input: num(u.input_tokens), output: num(u.output_tokens),
        cacheRead: num(u.cache_read_input_tokens), cacheWrite: num(u.cache_creation_input_tokens),
        cacheWrite1h: num(obj(u.cache_creation).ephemeral_1h_input_tokens) };
      // Streaming and resumed sessions write one response several times: the fullest count is the final one.
      const k = `${m.id}:${o.requestId}`, old = seen.get(k);
      if (!old || total(row) >= total(old)) seen.set(k, row);
    }
  });
  return { rows: [...seen.values()], bad };
}

function codex(since) {
  const root = env.CODEX_HOME || join(home, '.codex');
  const dirs = [join(root, 'sessions'), join(root, 'archived_sessions')];
  if (!dirs.some(existsSync)) return { error: `no session logs at ${dirs[0]}` };
  const rows = [], seen = new Set();
  const bad = each(recent(dirs, since, /\.jsonl$/), (f) => {
    let model = 'unknown', prev;
    for (const l of lines(f)) {
      if (!l.includes('"turn_context"') && !l.includes('"token_count"')) continue;
      let o; try { o = obj(JSON.parse(l)); } catch { continue; }
      const p = obj(o.payload);
      if (o.type === 'turn_context' && p.model) { model = p.model; continue; }
      const info = p.type === 'token_count' ? obj(p.info) : {}, t = info.total_token_usage;
      if (!t || typeof t !== 'object') continue;
      // The total is cumulative, so bill its growth. A fork starts from its parent's total: its first
      // count bills that turn only. History copied from another session (same time, same total) is skipped.
      const key = `${o.timestamp}|${JSON.stringify(t)}`, copied = seen.has(key);
      seen.add(key);
      const from = prev || (typeof info.last_token_usage === 'object' && info.last_token_usage ? null : {});
      const reset = from && num(t.total_tokens) < num(from.total_tokens);
      const d = (k) => (from ? num(num(t[k]) - (reset ? 0 : num(from[k]))) : num(info.last_token_usage[k]));
      const cached = d('cached_input_tokens');
      const row = { ts: o.timestamp, model, input: num(d('input_tokens') - cached), output: d('output_tokens'),
        cacheRead: cached, cacheWrite: d('cache_write_input_tokens'), cacheWrite1h: 0 };
      prev = t;
      if (!copied && total(row)) rows.push(row);
    }
  });
  return { rows, bad };
}

// opencode keeps messages in `session_message` (v2: model.id, any row type with tokens, compaction included)
// or `message` (v1: role assistant, modelID). Same columns out of both.
const OC = (since) => {
  const cols = (model) => `coalesce(json_extract(data,'$.time.created'), time_created), ${model}, json_extract(data,'$.tokens.input'),
    json_extract(data,'$.tokens.output'), json_extract(data,'$.tokens.reasoning'), json_extract(data,'$.tokens.cache.read'),
    json_extract(data,'$.tokens.cache.write')`;
  const where = `json_extract(data,'$.tokens') is not null and time_created >= ${Math.floor(since)}`;
  return {
    session_message: `select ${cols("json_extract(data,'$.model.id')")} from session_message where ${where}`,
    message: `select ${cols("json_extract(data,'$.modelID')")} from message where json_extract(data,'$.role') = 'assistant' and ${where}`,
  };
};
const OC_TABLES = "select name from sqlite_master where type = 'table' and name in ('session_message', 'message')";

// Returns query(sql) -> rows as arrays, through node:sqlite or else the sqlite3 command; throws with the reason.
async function sqlite(db) {
  let why = 'turned off';
  if (env.KAITO_USAGE_SQLITE !== 'cli') {
    const warn = process.emitWarning;
    process.emitWarning = () => {};  // node:sqlite is experimental and says so on every run
    try {
      const { DatabaseSync } = await import('node:sqlite');
      const d = new DatabaseSync(db, { readOnly: true });
      return { query: (sql) => d.prepare(sql).all().map((r) => Object.values(r)), close: () => d.close() };
    } catch (e) {
      if (e.code !== 'ERR_UNKNOWN_BUILTIN_MODULE') throw new Error(`could not open ${db}: ${e.message}`);
      why = e.message;
    } finally { process.emitWarning = warn; }
  }
  // -init with an empty file: sqlite3 then reads no ~/.sqliterc, which could run any command.
  const tmp = mkdtempSync(join(tmpdir(), 'kaito-usage-')), init = join(tmp, 'empty');
  writeFileSync(init, '');
  return {
    query: (sql) => {
      const r = spawnSync('sqlite3', ['-batch', '-init', init, '-readonly', '-separator', '\t', db, sql],
        { encoding: 'utf8', maxBuffer: 1 << 30 });
      if (r.error?.code === 'ENOENT') throw new Error(`this Node has no usable node:sqlite (${why}) and there is no sqlite3 command`);
      if (r.error || r.status !== 0) throw new Error(`sqlite3 could not read ${db}: ${r.error?.message || String(r.stderr).trim().split('\n').pop()}`);
      return r.stdout.split('\n').filter(Boolean).map((l) => l.split('\t'));
    },
    close: () => rmSync(tmp, { recursive: true, force: true }),
  };
}

async function opencode(since) {
  const db = join(env.XDG_DATA_HOME || join(home, '.local', 'share'), 'opencode', 'opencode.db');
  if (!existsSync(db)) return { error: `no database at ${db}` };
  const q = await sqlite(db), seen = new Map();
  try {
    const tables = q.query(OC_TABLES).map(([n]) => n);
    if (!tables.length) return { error: `unknown database layout in ${db} (no session_message or message table)` };
    for (const t of tables) {
      for (const [ts, model, i, o, reasoning, cr, cw] of q.query(OC(since)[t])) {
        const row = { ts: Number(ts), model: model || 'unknown', input: num(Number(i)), output: num(Number(o)) + num(Number(reasoning)),
          cacheRead: num(Number(cr)), cacheWrite: num(Number(cw)), cacheWrite1h: 0 };
        // A forked session copies its rows under new ids: same time, model and counts is the same response.
        if (total(row)) seen.set([row.ts, row.model, row.input, row.output, row.cacheRead, row.cacheWrite].join('|'), row);
      }
    }
  } finally { q.close(); }
  return { rows: [...seen.values()], bad: 0 };
}

function gemini(since) {
  // Gemini CLI uses the OS home, which on Windows (USERPROFILE) can differ from a shell's HOME.
  const homes = env.GEMINI_CLI_HOME ? [env.GEMINI_CLI_HOME] : [...new Set([home, env.USERPROFILE].filter(Boolean))];
  const dirs = homes.map((h) => join(h, '.gemini', 'tmp'));
  if (!dirs.some(existsSync)) return { error: `no session logs at ${dirs[0]}` };
  const seen = new Map();  // a message written again under the same id replaces the earlier one
  const add = (m) => {
    const t = obj(m).tokens;
    if (m?.type !== 'gemini' || !t || typeof t !== 'object' || typeof m.id !== 'string') return;
    const cached = num(t.cached);  // the prompt count includes the cached part
    seen.set(m.id, { ts: m.timestamp, model: m.model || 'unknown', input: num(num(t.input) - cached) + num(t.tool),
      output: num(t.output) + num(t.thoughts), cacheRead: cached, cacheWrite: 0, cacheWrite1h: 0 });
  };
  // A record is a message, or carries a whole message list: a legacy file, a metadata line, a $set checkpoint.
  const record = (r) => {
    add(r);
    for (const list of [obj(r).messages, obj(obj(r).$set).messages]) if (Array.isArray(list)) list.forEach(add);
  };
  const bad = each(recent(dirs, since, /[\\/]chats[\\/].*\.jsonl?$/), (f) => {
    if (f.endsWith('.json')) return record(JSON.parse(readFileSync(f, 'utf8')));
    for (const l of lines(f)) { if (l.includes('"tokens"')) try { record(JSON.parse(l)); } catch {} }
  });
  return { rows: [...seen.values()], bad };
}

const RUNNERS = [['claude', claude], ['codex', codex], ['opencode', opencode], ['gemini', gemini],
  ['cursor-agent', () => ({ error: 'Cursor keeps no token counts on disk' })]];

// ---- prices

// A row prices a model when the id is the row's family name, after nothing but vendor or region labels and
// before nothing but version, date or effort parts: "claude-opus-5" prices anthropic/claude-opus-5-7-20270101;
// "gpt-5" does not price gpt-5-mini, and "chat-latest" does not price gpt-5-chat-latest.
const flat = (s) => String(s).toLowerCase().replace(/^.*\//, '').replace(/\./g, '-');
const HEAD = /^((us|eu|apac|global|anthropic|openai|google|xai|vertex|bedrock|azure|models)-)*$/;
const TAIL = /^([-@:](\d+|v\d+|latest|preview|low|medium|high|xhigh|max|thinking|fast))*$/;
function priceOf(model, list) {
  const id = flat(model);
  return list.find((p) => {
    const fam = flat(p.match);
    for (let i = id.indexOf(fam); i !== -1; i = id.indexOf(fam, i + 1)) {
      if (HEAD.test(id.slice(0, i)) && TAIL.test(id.slice(i + fam.length))) return true;
    }
    return false;
  });
}
const price = (v) => typeof v === 'number' && v >= 0;
const validRow = (p) => p && typeof p.match === 'string' && p.match && price(p.input) && price(p.output) &&
  ['cache_read', 'cache_write', 'cache_write_1h'].every((k) => p[k] == null || price(p[k]));
// USD for one row. A cache price the vendor does not publish (null) is charged at the input price;
// a list with no 1-hour write price at all uses its 5-minute one.
function costOf(r, p) {
  const or = (v) => (v == null ? p.input : v);
  const w1 = Math.min(r.cacheWrite1h, r.cacheWrite);
  return (r.input * p.input + r.output * p.output + r.cacheRead * or(p.cache_read) +
    (r.cacheWrite - w1) * or(p.cache_write) + w1 * or(p.cache_write_1h === undefined ? p.cache_write : p.cache_write_1h)) / 1e6;
}

// ---- report

const TIERS = ['light', 'standard', 'hard', 'frontier'];
const n = (v) => Math.round(v).toLocaleString('en-US');
const usd = (v) => '$' + v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

async function report(arg) {
  const days = arg === undefined ? 7 : Number(arg);
  if (!Number.isInteger(days) || days < 1 || days > 3660) { console.error('usage: kaito-usage.mjs report [days]'); process.exit(2); }
  const first = shift(today, 1 - days);
  const [y, m, d] = first.split('-').map(Number);
  const since = new Date(y, m - 1, d).getTime();  // local midnight of the first day
  const prices = JSON.parse(readFileSync(env.KAITO_PRICES || join(here, '..', 'references', 'prices.json'), 'utf8'));
  const list = (Array.isArray(prices.models) ? prices.models : []).filter(validRow);
  const badRows = (Array.isArray(prices.models) ? prices.models.length : 0) - list.length;

  const cells = new Map(), status = [];
  for (const [name, read] of RUNNERS) {
    let res; try { res = await read(since); } catch (e) { res = { error: e.message }; }
    if (res.error) { status.push(`  ${name}: not readable, ${res.error}`); continue; }
    let used = 0;
    for (const r of res.rows) {
      const day = dayOf(r.ts), model = String(r.model);
      if (!day || day < first || day > today) continue;
      used++;
      const k = `${day}\t${model}`;
      const c = cells.get(k) || cells.set(k, { day, model, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cacheWrite1h: 0 }).get(k);
      for (const f of ['input', 'output', 'cacheRead', 'cacheWrite', 'cacheWrite1h']) c[f] += r[f];
    }
    status.push(`  ${name}: read, ${n(used)} model responses in the window` +
      (res.bad ? `; ${n(res.bad)} log file${res.bad === 1 ? '' : 's'} could not be read and ${res.bad === 1 ? 'is' : 'are'} not counted` : ''));
  }

  console.log(`Usage for the last ${days} day${days === 1 ? '' : 's'} (${first} to ${today}), read from this machine only.`);
  console.log(`Prices are estimates: ${prices.currency} list prices ${prices.unit} as of ${prices.updated}, not a bill. Subscription plans are not billed per token.`);
  console.log('');
  const table = [['day', 'model', 'input', 'output', 'cache read', 'cache write', 'est. price']];
  const sum = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, byModel = new Map(), noPrice = new Map();
  let cost = 0;
  const sorted = [...cells.values()].sort((a, b) => (a.day < b.day ? 1 : a.day > b.day ? -1 : total(b) - total(a)));
  for (const c of sorted) {
    const p = priceOf(c.model, list);
    byModel.set(c.model, (byModel.get(c.model) || 0) + total(c));
    if (p) { cost += costOf(c, p); for (const f of Object.keys(sum)) sum[f] += c[f]; }
    else noPrice.set(c.model, (noPrice.get(c.model) || 0) + total(c));
    table.push([c.day, c.model, n(c.input), n(c.output), n(c.cacheRead), n(c.cacheWrite), p ? usd(costOf(c, p)) : 'no price']);
  }
  if (sorted.length) table.push(['total', noPrice.size ? '(priced models)' : '', n(sum.input), n(sum.output), n(sum.cacheRead), n(sum.cacheWrite), usd(cost)]);
  else console.log('No usage found in this window.');
  const w = table[0].map((_, i) => table.reduce((max, r) => Math.max(max, r[i].length), 0));
  if (sorted.length) for (const r of table) console.log(r.map((c, i) => (i < 2 ? c.padEnd(w[i]) : c.padStart(w[i]))).join('  ').trimEnd());
  for (const [model, t] of noPrice) console.log(`No price for ${model} (${n(t)} tokens): it is not in prices.json, so it is left out of the total.`);
  if (badRows) console.log(`prices.json has ${n(badRows)} row${badRows === 1 ? '' : 's'} with a missing or non-number price; ${badRows === 1 ? 'it is' : 'they are'} ignored.`);

  console.log('');
  console.log('Runners:');
  for (const s of status) console.log(s);

  if (!byModel.size) return;
  console.log('');
  const [main] = [...byModel].sort((a, b) => b[1] - a[1])[0];
  const all = [...byModel.values()].reduce((a, b) => a + b, 0);
  const head = `Main model: ${main} (the model with the most tokens in the window, cache included).`;
  let tierOf;
  try { ({ tierOf } = await import(pathToFileURL(env.KAITO_MODELS_MODULE || join(here, 'kaito-models.mjs')).href)); } catch {}
  if (typeof tierOf !== 'function') return console.log(`${head} Cheaper tiers: tier split unavailable (kaito-models.mjs not found).`);
  const rank = (model) => { try { return TIERS.indexOf(tierOf(model)); } catch { return -1; } };
  const top = rank(main);
  if (top < 0) return console.log(`${head} Cheaper tiers: tier split unavailable (no tier known for ${main}).`);
  const per = TIERS.map(() => 0); let unknown = 0;
  for (const [model, t] of byModel) { const r = rank(model); if (r < 0) unknown += t; else per[r] += t; }
  const cheaper = per.slice(0, top).reduce((a, b) => a + b, 0);
  const parts = TIERS.slice(0, top).map((t, i) => `${t} ${n(per[i])}`).join(', ');
  console.log(`${head} Its tier is ${TIERS[top]}.`);
  console.log(`Cheaper tiers: ${n(cheaper)} of ${n(all)} tokens (${Math.round((cheaper / all) * 100)}%) went to a cheaper tier than the main model${parts ? ` (${parts})` : ''}.` +
    (unknown ? ` ${n(unknown)} tokens are on models with no known tier.` : ''));
}

// ---- consent before a pay-per-token route

// A CLI is pay-per-token when one of these keys is set (it then bills the key, not the login),
// or when its own files say it is signed in with an API key.
const KEYS = { anthropic: ['ANTHROPIC_API_KEY'], openai: ['OPENAI_API_KEY', 'CODEX_API_KEY'],
  google: ['GEMINI_API_KEY', 'GOOGLE_API_KEY'], xai: ['XAI_API_KEY'] };
const CLI_VENDOR = { claude: 'anthropic', codex: 'openai', gemini: 'google' };
const SUBSCRIPTION = ['host', 'cursor-agent'];  // host subagents and Cursor run on the login
// Local Ollama is free and sends nothing out. A cloud model (its name ends in cloud) runs on Ollama's servers, so that one asks.
const isLocalOllama = (r, model) => r === 'ollama' && !/(^|[:-])cloud$/i.test(model);
const keySet = (vendor) => (KEYS[vendor] || []).some((k) => env[k]);  // presence only, never printed
const STORED = {
  // Codex auth.json: auth_mode "apikey" (or a Bedrock key), or an older file holding a key and no ChatGPT tokens.
  codex: () => {
    const a = obj(json(join(env.CODEX_HOME || join(home, '.codex'), 'auth.json')));
    const mode = String(a.auth_mode || '').toLowerCase().replace(/[^a-z]/g, '');
    return mode ? /key/.test(mode) : Boolean(a.OPENAI_API_KEY) && !a.tokens;
  },
  // Gemini settings.json: any recorded auth type other than the Google login is an API key, Vertex or a gateway.
  gemini: () => {
    if (/^true$/i.test(env.GOOGLE_GENAI_USE_VERTEXAI || '')) return true;
    const s = obj(json(join(env.GEMINI_CLI_HOME || home, '.gemini', 'settings.json')));
    const type = obj(obj(s.security).auth).selectedType || s.selectedAuthType;
    return typeof type === 'string' && type !== 'oauth-personal';
  },
};

function payPerToken(runner, model) {
  const r = runner.toLowerCase();
  if (SUBSCRIPTION.includes(r) || isLocalOllama(r, model)) return false;
  if (CLI_VENDOR[r]) return keySet(CLI_VENDOR[r]) || Boolean(STORED[r]?.());
  if (r === 'opencode') {  // provider/id
    const provider = model.includes('/') ? model.split('/')[0].toLowerCase() : '';
    return provider === 'openrouter' || provider === '' || (KEYS[provider] ? keySet(provider) : true);
  }
  return true;  // openrouter, api, xai and anything unknown: a key pays for it
}

function consent([sub, a, b]) {
  const file = join(kaitoHome, 'usage-consent.json');
  const seen = obj(json(file));
  if (sub === 'check' && a && b) return console.log(payPerToken(a, b) && seen[b] !== today ? 'ask' : 'ok');
  if (sub === 'yes' && a) {
    const keep = Object.fromEntries(Object.entries(seen).filter(([, d]) => d === today));  // a yes ends with its day
    keep[a] = today;
    mkdirSync(kaitoHome, { recursive: true });
    writeFileSync(file, JSON.stringify(keep, null, 2) + '\n');
    return console.log(`ok: ${a} until the end of ${today}`);
  }
  console.error('usage: kaito-usage.mjs consent check <runner> <model> | consent yes <model>');
  process.exit(2);
}

const [cmd, ...rest] = process.argv.slice(2);
if (cmd === 'report') await report(rest[0]);
else if (cmd === 'consent') consent(rest);
else {
  console.error('usage: kaito-usage.mjs report [days] | consent check <runner> <model> | consent yes <model>');
  process.exit(2);
}
