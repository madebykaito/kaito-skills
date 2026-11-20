// Token usage per day and model, read from the runners' own logs on this machine. No network calls.
//   node kaito-usage.mjs report [days]                  table for the last <days> days (default 7)
//   node kaito-usage.mjs consent check <runner> <model>  prints ask (pay-per-token, no yes today) or ok
//   node kaito-usage.mjs consent yes <model>             records today's yes under ~/.kaito
// KAITO_TODAY=YYYY-MM-DD replaces today's date (tests).
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const env = process.env;
const here = dirname(fileURLToPath(import.meta.url));
const home = env.HOME || homedir();
const kaitoHome = env.KAITO_HOME || join(home, '.kaito');
const pad = (n) => String(n).padStart(2, '0');
const dayOf = (t) => {  // local calendar day; '' for a bad timestamp
  const d = new Date(t);
  return isNaN(d) ? '' : `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const today = /^\d{4}-\d\d-\d\d$/.test(env.KAITO_TODAY || '') ? env.KAITO_TODAY : dayOf(Date.now());
const num = (v) => (Number.isFinite(v) && v > 0 ? v : 0);
const lines = (file) => readFileSync(file, 'utf8').split('\n');
const walk = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
  e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)]);
// Log files under dir that changed inside the window, so old sessions are never opened.
const recent = (dir, since, re) => walk(dir).filter((f) => re.test(f) && statSync(f).mtimeMs >= since);

// ---- collectors: each returns { rows: [{ ts, model, input, output, cacheRead, cacheWrite, cacheWrite1h }] }
// or { error: reason }. input never includes cached tokens.

function claude(since) {
  const dir = join(env.CLAUDE_CONFIG_DIR || join(home, '.claude'), 'projects');
  if (!existsSync(dir)) return { error: `no session logs at ${dir}` };
  const seen = new Map();  // streaming writes one response several times: the last line wins
  for (const f of recent(dir, since, /\.jsonl$/)) {
    for (const l of lines(f)) {
      if (!l.includes('"usage"')) continue;
      let o; try { o = JSON.parse(l); } catch { continue; }
      const m = o.message, u = m?.usage;
      if (!u || !m.model || m.model === '<synthetic>') continue;
      const h1 = num(u.cache_creation?.ephemeral_1h_input_tokens);
      seen.set(`${m.id}:${o.requestId}`, {
        ts: o.timestamp, model: m.model, input: num(u.input_tokens), output: num(u.output_tokens),
        cacheRead: num(u.cache_read_input_tokens), cacheWrite: num(u.cache_creation_input_tokens), cacheWrite1h: h1,
      });
    }
  }
  return { rows: [...seen.values()] };
}

function codex(since) {
  const dir = join(env.CODEX_HOME || join(home, '.codex'), 'sessions');
  if (!existsSync(dir)) return { error: `no session logs at ${dir}` };
  const rows = [];
  for (const f of recent(dir, since, /\.jsonl$/)) {
    let model = 'unknown', prev = {};
    for (const l of lines(f)) {
      if (!l.includes('"turn_context"') && !l.includes('"token_count"')) continue;
      let o; try { o = JSON.parse(l); } catch { continue; }
      if (o.type === 'turn_context' && o.payload?.model) { model = o.payload.model; continue; }
      const t = o.payload?.type === 'token_count' && o.payload.info?.total_token_usage;
      if (!t) continue;
      // The total is cumulative per session, and the same count can be logged twice: bill the growth only.
      const reset = num(t.total_tokens) < num(prev.total_tokens);
      const d = (k) => num(num(t[k]) - (reset ? 0 : num(prev[k])));
      const cached = d('cached_input_tokens');
      const row = { ts: o.timestamp, model, input: num(d('input_tokens') - cached), output: d('output_tokens'),
        cacheRead: cached, cacheWrite: d('cache_write_input_tokens'), cacheWrite1h: 0 };
      prev = t;
      if (row.input + row.output + row.cacheRead + row.cacheWrite) rows.push(row);
    }
  }
  return { rows };
}

const OC_SQL = (since) => `select time_created, json_extract(data,'$.model.id'), json_extract(data,'$.tokens.input'),
  json_extract(data,'$.tokens.output'), json_extract(data,'$.tokens.reasoning'), json_extract(data,'$.tokens.cache.read'),
  json_extract(data,'$.tokens.cache.write') from session_message where type='assistant' and time_created >= ${Math.floor(since)}`;

async function opencode(since) {
  const db = join(env.XDG_DATA_HOME || join(home, '.local', 'share'), 'opencode', 'opencode.db');
  if (!existsSync(db)) return { error: `no database at ${db}` };
  let recs, why;
  const warn = process.emitWarning;
  process.emitWarning = () => {};  // node:sqlite is experimental and says so on every run
  try {
    const { DatabaseSync } = await import('node:sqlite');
    const d = new DatabaseSync(db, { readOnly: true });
    try { recs = d.prepare(OC_SQL(since)).all().map((r) => Object.values(r)); } finally { d.close(); }
  } catch (e) { why = e.message; } finally { process.emitWarning = warn; }
  if (!recs) {
    const r = spawnSync('sqlite3', ['-readonly', '-separator', '\t', db, OC_SQL(since)], { encoding: 'utf8' });
    if (r.error) return { error: `this Node has no usable node:sqlite (${why}) and there is no sqlite3 command` };
    if (r.status !== 0) return { error: `sqlite3 could not read ${db}: ${(r.stderr || '').trim().split('\n')[0]}` };
    recs = r.stdout.split('\n').filter(Boolean).map((l) => l.split('\t'));
  }
  const rows = recs.map(([ts, model, i, o, reasoning, cr, cw]) => ({ ts: Number(ts), model: model || 'unknown',
    input: num(Number(i)), output: num(Number(o)) + num(Number(reasoning)), cacheRead: num(Number(cr)),
    cacheWrite: num(Number(cw)), cacheWrite1h: 0 }));
  return { rows: rows.filter((r) => r.input + r.output + r.cacheRead + r.cacheWrite) };
}

function gemini(since) {
  const dir = join(env.GEMINI_CLI_HOME || home, '.gemini', 'tmp');
  if (!existsSync(dir)) return { error: `no session logs at ${dir}` };
  const seen = new Map();  // a message can be written again under the same id: the last one wins
  for (const f of recent(dir, since, /[\\/]chats[\\/].*\.jsonl?$/)) {
    let msgs = [];
    if (f.endsWith('.json')) { try { msgs = JSON.parse(readFileSync(f, 'utf8')).messages || []; } catch { continue; } }
    else for (const l of lines(f)) { if (l.includes('"tokens"')) try { msgs.push(JSON.parse(l)); } catch {} }
    for (const m of msgs) {
      const t = m?.tokens;
      if (m?.type !== 'gemini' || !t || !m.id) continue;
      const cached = num(t.cached);  // the prompt count includes the cached part
      seen.set(m.id, { ts: m.timestamp, model: m.model || 'unknown', input: num(num(t.input) - cached) + num(t.tool),
        output: num(t.output) + num(t.thoughts), cacheRead: cached, cacheWrite: 0, cacheWrite1h: 0 });
    }
  }
  return { rows: [...seen.values()] };
}

const RUNNERS = [['claude', claude], ['codex', codex], ['opencode', opencode], ['gemini', gemini],
  ['cursor-agent', () => ({ error: 'Cursor keeps no token counts on disk' })]];

// ---- prices

// A row prices a model when the id holds the row's family name followed by nothing but version,
// date or effort parts: "opus-5" prices claude-opus-5-7-20270101, "gpt-5" does not price gpt-5-mini.
const flat = (s) => String(s).toLowerCase().replace(/^.*\//, '').replace(/\./g, '-');
const TAIL = /^([-@:](\d+|v\d+|latest|preview|low|medium|high|xhigh|max|thinking|fast))*$/;
function priceOf(model, list) {
  const id = flat(model);
  return list.find((p) => {
    const fam = flat(p.match);
    for (let i = id.indexOf(fam); i !== -1; i = id.indexOf(fam, i + 1)) {
      if ((i === 0 || id[i - 1] === '-') && TAIL.test(id.slice(i + fam.length))) return true;
    }
    return false;
  });
}
// USD for one row. A cache price the vendor does not publish (null) is charged at the input price.
function costOf(r, p) {
  const or = (v) => (v == null ? p.input : v);
  const w1 = Math.min(r.cacheWrite1h, r.cacheWrite);
  return (r.input * p.input + r.output * p.output + r.cacheRead * or(p.cache_read) +
    (r.cacheWrite - w1) * or(p.cache_write) + w1 * or(p.cache_write_1h ?? p.cache_write)) / 1e6;
}

// ---- report

const TIERS = ['light', 'standard', 'hard', 'frontier'];
const n = (v) => Math.round(v).toLocaleString('en-US');
const usd = (v) => '$' + v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const total = (r) => r.input + r.output + r.cacheRead + r.cacheWrite;

async function report(arg) {
  const days = arg === undefined ? 7 : Number(arg);
  if (!Number.isInteger(days) || days < 1 || days > 3660) { console.error('usage: kaito-usage.mjs report [days]'); process.exit(2); }
  const end = new Date(`${today}T12:00:00`);
  const first = dayOf(end.getTime() - (days - 1) * 864e5);
  const since = new Date(`${first}T00:00:00`).getTime();
  const prices = JSON.parse(readFileSync(env.KAITO_PRICES || join(here, '..', 'references', 'prices.json'), 'utf8'));

  const cells = new Map(), status = [];
  for (const [name, read] of RUNNERS) {
    let res; try { res = await read(since); } catch (e) { res = { error: e.message }; }
    if (res.error) { status.push(`  ${name}: not readable, ${res.error}`); continue; }
    let used = 0;
    for (const r of res.rows) {
      const day = dayOf(r.ts);
      if (!day || day < first || day > today) continue;
      used++;
      const k = `${day}\t${r.model}`;
      const c = cells.get(k) || cells.set(k, { day, model: r.model, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cacheWrite1h: 0 }).get(k);
      for (const f of ['input', 'output', 'cacheRead', 'cacheWrite', 'cacheWrite1h']) c[f] += r[f];
    }
    status.push(`  ${name}: read, ${n(used)} model responses in the window`);
  }

  console.log(`Usage for the last ${days} day${days === 1 ? '' : 's'} (${first} to ${today}), read from this machine only.`);
  console.log(`Prices are estimates: ${prices.currency} list prices ${prices.unit} as of ${prices.updated}, not a bill. Subscription plans are not billed per token.`);
  console.log('');
  const table = [['day', 'model', 'input', 'output', 'cache read', 'cache write', 'est. price']];
  const sum = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, byModel = new Map(), noPrice = new Map();
  let cost = 0;
  const sorted = [...cells.values()].sort((a, b) => (a.day < b.day ? 1 : a.day > b.day ? -1 : total(b) - total(a)));
  for (const c of sorted) {
    const p = priceOf(c.model, prices.models);
    byModel.set(c.model, (byModel.get(c.model) || 0) + total(c));
    if (p) { cost += costOf(c, p); for (const f of Object.keys(sum)) sum[f] += c[f]; }
    else noPrice.set(c.model, (noPrice.get(c.model) || 0) + total(c));
    table.push([c.day, c.model, n(c.input), n(c.output), n(c.cacheRead), n(c.cacheWrite), p ? usd(costOf(c, p)) : 'no price']);
  }
  if (sorted.length) table.push(['total', noPrice.size ? '(priced models)' : '', n(sum.input), n(sum.output), n(sum.cacheRead), n(sum.cacheWrite), usd(cost)]);
  else console.log('No usage found in this window.');
  const w = table[0].map((_, i) => Math.max(...table.map((r) => r[i].length)));
  if (sorted.length) for (const r of table) console.log(r.map((c, i) => (i < 2 ? c.padEnd(w[i]) : c.padStart(w[i]))).join('  ').trimEnd());
  for (const [m, t] of noPrice) console.log(`No price for ${m} (${n(t)} tokens): it is not in prices.json, so it is left out of the total.`);

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
  const rank = (m) => { try { return TIERS.indexOf(tierOf(m)); } catch { return -1; } };
  const top = rank(main);
  if (top < 0) return console.log(`${head} Cheaper tiers: tier split unavailable (no tier known for ${main}).`);
  const per = TIERS.map(() => 0); let unknown = 0;
  for (const [m, t] of byModel) { const r = rank(m); if (r < 0) unknown += t; else per[r] += t; }
  const cheaper = per.slice(0, top).reduce((a, b) => a + b, 0);
  const parts = TIERS.slice(0, top).map((t, i) => `${t} ${n(per[i])}`).join(', ');
  console.log(`${head} Its tier is ${TIERS[top]}.`);
  console.log(`Cheaper tiers: ${n(cheaper)} of ${n(all)} tokens (${Math.round((cheaper / all) * 100)}%) went to a cheaper tier than the main model${parts ? ` (${parts})` : ''}.` +
    (unknown ? ` ${n(unknown)} tokens are on models with no known tier.` : ''));
}

// ---- consent before a pay-per-token route

// A CLI is pay-per-token when one of these keys is set (it then bills the key, not the login).
const KEYS = { anthropic: ['ANTHROPIC_API_KEY'], openai: ['OPENAI_API_KEY', 'CODEX_API_KEY'],
  google: ['GEMINI_API_KEY', 'GOOGLE_API_KEY'], xai: ['XAI_API_KEY'] };
const CLI_VENDOR = { claude: 'anthropic', codex: 'openai', gemini: 'google' };
const SUBSCRIPTION = ['host', 'cursor-agent'];  // host subagents and Cursor run on the login
const keySet = (vendor) => (KEYS[vendor] || []).some((k) => env[k]);  // presence only, never printed

function payPerToken(runner, model) {
  const r = runner.toLowerCase();
  if (SUBSCRIPTION.includes(r)) return false;
  if (CLI_VENDOR[r]) return keySet(CLI_VENDOR[r]);
  if (r === 'opencode') {  // provider/id
    const provider = model.includes('/') ? model.split('/')[0].toLowerCase() : '';
    return provider === 'openrouter' || provider === '' || (KEYS[provider] ? keySet(provider) : true);
  }
  return true;  // openrouter, api, xai and anything unknown: a key pays for it
}

function consent([sub, a, b]) {
  const file = join(kaitoHome, 'usage-consent.json');
  let seen = {};
  try { seen = JSON.parse(readFileSync(file, 'utf8')) || {}; } catch {}
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
