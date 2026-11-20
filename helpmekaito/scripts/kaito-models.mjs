#!/usr/bin/env node
// Which model to delegate to, worked out from what is installed here. No network, never prints a key.
//   kaito-models.mjs tier <model-id>                  the tier the name rule gives the id
//   kaito-models.mjs resolve <vendor-or-runner> <tier> newest reachable model: "<runner> <model-id>"
//   kaito-models.mjs detect                           find the agent CLIs and store the list
//   kaito-models.mjs agents                           print the stored list (found again when a day old)
//   kaito-models.mjs fail <runner> <model>            record a failure: resolve skips that model today
//   kaito-models.mjs list [filter]                    every model per runner, for models-available.sh
// Vendors: anthropic openai google xai, or the first word of a model id (kimi, deepseek).
// When nothing fits, the line starts with "host:" and says why: use the host's own model.
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, realpathSync } from 'node:fs';
import { join, dirname, delimiter } from 'node:path';
import { homedir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const TIERS = ['light', 'standard', 'hard', 'frontier'];
// The rule: the tier is the family word in the id, never the version, so a new release needs no change here.
// First match wins; the words for a shrunk model come first ("flash-lite" and "pro-mini" are light).
const RULE = [
  ['light', ['lite', 'mini', 'nano', 'haiku', 'luna', 'hydrogen']],
  ['frontier', ['fable', 'astra', 'ultra', 'carbon']],
  ['hard', ['opus', 'sol', 'pro', 'argon']],
  ['standard', ['sonnet', 'terra', 'flash']],
];
const words = (id) => String(id).toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);

export function tierOf(modelId) {
  const w = words(modelId);
  for (const [tier, names] of RULE) if (names.some((n) => w.includes(n))) return tier;
  return null;
}

// Native CLIs first: a vendor's own runner wins a tie.
const RUNNERS = ['claude', 'codex', 'gemini', 'cursor-agent', 'opencode', 'copilot', 'ollama'];
const VENDORS = { anthropic: ['claude', 'haiku', 'sonnet', 'opus', 'fable'], openai: ['gpt'], google: ['gemini'], xai: ['grok'] };
const K = process.env.KAITO_HOME || join(process.env.HOME || homedir(), '.kaito');
const DAY = 86400000;

const readJson = (f) => { try { return JSON.parse(readFileSync(f, 'utf8')); } catch { return {}; } };
const writeJson = (f, v) => { mkdirSync(K, { recursive: true }); writeFileSync(f, JSON.stringify(v, null, 2) + '\n'); };
const today = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };

function which(name) {
  const exts = process.platform === 'win32' ? ['', '.exe', '.cmd', '.bat'] : [''];
  for (const dir of (process.env.PATH || '').split(delimiter)) {
    for (const e of exts) {
      const p = join(dir, name + e);
      try { if (dir && statSync(p).isFile()) return p; } catch {}
    }
  }
  return null;
}
// Through sh: on Windows the CLIs are shell or .cmd shims that node cannot start directly.
function run(cmd) {
  try { return execFileSync('sh', ['-c', cmd], { encoding: 'utf8', timeout: 20000, stdio: ['ignore', 'pipe', 'ignore'] }).split(/\r?\n/); } catch { return []; }
}

function detect() {
  const agents = RUNNERS.filter(which);
  writeJson(join(K, 'agents.json'), { at: Date.now(), agents });
  return agents;
}
function agents() {
  const s = readJson(join(K, 'agents.json'));
  return Array.isArray(s.agents) && Date.now() - s.at < DAY ? s.agents : detect();
}
const say = (a) => `agents: ${a.join(' ') || 'none found'}`;

// Gemini CLI has no listing command: its model ids are the string constants in the installed bundle.
function geminiModels() {
  let dir;
  try { dir = dirname(realpathSync(which('gemini'))); } catch { return []; }
  const pkg = join('node_modules', '@google', 'gemini-cli', 'bundle');
  const ids = new Set(), loose = new Set();
  for (const b of [dir, join(dir, pkg), join(dir, '..', 'lib', pkg)]) {
    let files = [];
    try { files = readdirSync(b).filter((f) => f.endsWith('.js')); } catch {}
    for (const f of files) {
      let t = '';
      try { t = readFileSync(join(b, f), 'utf8'); } catch {}
      for (const m of t.matchAll(/MODEL[A-Z0-9_]*\s*=\s*"(gemini-\d[a-z0-9.-]*[a-z0-9])"/g)) ids.add(m[1]);
      for (const m of t.matchAll(/"(gemini-\d[a-z0-9.-]*[a-z0-9])"/g)) loose.add(m[1]);
    }
    if (loose.size) break;
  }
  // Not for delegating: internal variants and image, embedding, live and computer-use models.
  const junk = /-(base|customtools)$|image|embedding|live|computer-use|tts|audio/;
  return [...(ids.size ? ids : loose)].filter((id) => !junk.test(id)).sort();
}

// The lines a runner's listing prints; the model id is the first word of each.
const LIST = {
  claude: () => ['haiku', 'sonnet', 'opus', 'fable'],  // aliases: each always points at the newest of its family
  codex: () => {
    let t = '';
    try { t = readFileSync(join(process.env.CODEX_HOME || join(process.env.HOME || homedir(), '.codex'), 'models_cache.json'), 'utf8'); } catch {}
    return [...new Set([...t.matchAll(/"slug":\s*"([^"]+)"/g)].map((m) => m[1]))].sort();
  },
  gemini: geminiModels,
  'cursor-agent': () => run('cursor-agent --list-models').filter((l) => l.includes(' - ')),
  opencode: () => run('opencode models'),
  copilot: () => [],  // no listing command in its docs: /model inside a session
  ollama: () => run('ollama ls').slice(1),
};
const NOTE = {
  claude: ' (aliases)',
  gemini: ' (read from the installed CLI; none means its bundle was not found)',
  copilot: ' (cannot be listed: run /model inside copilot)',
};
function models(runner) {
  return LIST[runner]().map((l) => l.trim()).filter(Boolean);
}

// "provider/claude-opus-5-5-thinking-high-fast" -> the model without provider, effort and speed, and how plain it is.
const EFFORT = ['medium', 'high', 'low', 'xhigh', 'max', 'minimal', 'none'];
function parse(id) {
  const w = words(id.slice(id.indexOf('/') + 1));
  let cost = 0;
  for (;;) {
    const last = w[w.length - 1];
    if (last === 'fast') cost += 100;
    else if (last === 'thinking') cost += 10;
    else if (EFFORT.includes(last)) cost += EFFORT.indexOf(last) + 1;
    else break;
    w.pop();
  }
  const base = w.join('-');
  // Version: the short numbers in the id, in order. Longer ones are dates. An alias has none and means "newest".
  const nums = (base.match(/\d+/g) || []).filter((n) => n.length < 4).map(Number);
  const vendor = Object.keys(VENDORS).find((v) => VENDORS[v].some((n) => w.includes(n))) || w[0];
  return { base, cost, vendor, version: nums.length ? nums : [Infinity], preview: /preview|beta|alpha|exp/.test(base) };
}
function newer(a, b) {
  for (let i = 0; i < Math.max(a.version.length, b.version.length); i++) {
    const d = (a.version[i] ?? -1) - (b.version[i] ?? -1);
    if (d) return d > 0;
  }
  if (a.preview !== b.preview) return b.preview;
  return a.cost < b.cost;  // same model: the plain id, then medium effort
}

function resolve(name, tier) {
  const have = agents();
  const host = (why) => [`host: ${why}; use the host's model`];
  if (RUNNERS.includes(name) && !have.includes(name)) return host(`${name} is not installed here`);
  const f = readJson(join(K, 'model-failures.json'));
  const failed = f.date === today() && Array.isArray(f.failed) ? f.failed : [];
  const best = {};  // vendor -> pick
  for (const runner of RUNNERS.includes(name) ? [name] : have) {
    for (const line of models(runner)) {
      const id = line.split(/\s+/)[0], m = { runner, id, ...parse(id) };
      // Privacy (models.md): no listing marked NO ZDR, no free tier that may train on what it is sent.
      if (tierOf(m.base) !== tier || line.includes('NO ZDR') || words(id).includes('free')) continue;
      if (!RUNNERS.includes(name) && m.vendor !== name) continue;
      if (failed.includes(`${runner} ${m.base}`)) continue;
      if (!best[m.vendor] || newer(m, best[m.vendor])) best[m.vendor] = m;
    }
  }
  const out = Object.values(best).map((m) => `${m.runner} ${m.id}`);
  return out.length ? out : host(`no ${tier} model reachable for ${name} today`);
}

function fail(runner, model) {
  const file = join(K, 'model-failures.json'), f = readJson(file), key = `${runner} ${parse(model).base}`;
  const failed = f.date === today() && Array.isArray(f.failed) ? f.failed : [];
  if (!failed.includes(key)) failed.push(key);
  writeJson(file, { date: today(), failed });
  return `failed today: ${runner} ${model}`;
}

function list(filter = '.') {
  const re = new RegExp(filter, 'i'), out = [];
  for (const r of RUNNERS.filter(which)) {
    out.push(`MODELS ${r}${NOTE[r] || ''}`, ...models(r).filter((l) => re.test(l)).slice(0, 80).map((l) => `  ${l}`));
  }
  return out;
}

function main([cmd, a, b]) {
  const usage = () => { console.error('usage: kaito-models.mjs tier <model-id> | resolve <vendor-or-runner> <light|standard|hard|frontier> | detect | agents | fail <runner> <model> | list [filter]'); process.exit(2); };
  if (cmd === 'tier' && a) console.log(tierOf(a) || `host: the tier rule cannot place "${a}"; use the host's model`);
  else if (cmd === 'resolve' && a && TIERS.includes(b)) console.log(resolve(a.toLowerCase(), b).join('\n'));
  else if (cmd === 'detect') console.log(say(detect()));
  else if (cmd === 'agents') console.log(say(agents()));
  else if (cmd === 'fail' && a && b) console.log(fail(a, b));
  else if (cmd === 'list') { const l = list(a); if (l.length) console.log(l.join('\n')); }
  else usage();
}

// Run only as a script, not on import. Real paths: the skill folder is reached through a link.
let isMain = false;
try { isMain = realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); } catch {}
if (isMain) main(process.argv.slice(2));
