#!/usr/bin/env node
// Run prompts through a local Ollama server over its HTTP API, so it works without the ollama CLI.
// Local and free: nothing leaves the machine. There is no key to print.
//   kaito-ollama.mjs run <model> [--translate-to <lang>] [--timeout <sec>] < prompt   one prompt on stdin, the text on stdout
//   kaito-ollama.mjs bulk <model> <prompts.jsonl> [--out <file>] [--concurrency <n>] [--translate-to <lang>] [--timeout <sec>]
//   kaito-ollama.mjs tags                                                             the pulled models as JSON
// A bulk input line is a JSON string or an object with "prompt" (and optionally "id"). Output is one JSON line per
// input line, in input order: {"i":0,"id":..,"text":".."} or {"i":0,"error":".."}. Exit 1 when any line failed.
// The server is OLLAMA_HOST (default http://127.0.0.1:11434).
import { readFileSync, writeFileSync, realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// OLLAMA_HOST may be "host", "host:port", "http://host:port"; 0.0.0.0 is a listen address, not one to call.
export function ollamaBase(raw = process.env.OLLAMA_HOST) {
  let h = String(raw || '').trim() || 'http://127.0.0.1:11434';
  if (!/^https?:\/\//i.test(h)) h = `http://${h}`;
  let u;
  try { u = new URL(h); } catch { throw new Error(`OLLAMA_HOST "${h}" is not a valid address`); }
  if (u.hostname === '0.0.0.0' || u.hostname === '[::]') u.hostname = '127.0.0.1';
  if (!u.port && !/^https:/i.test(h) && !/:80(\/|$)/.test(h.replace(/^https?:\/\//i, ''))) u.port = '11434';
  return u.origin + u.pathname.replace(/\/+$/, '');  // a reverse proxy may serve it under a path
}

const LANGS = { bn: 'Bengali', hi: 'Hindi', ta: 'Tamil', te: 'Telugu', mr: 'Marathi', gu: 'Gujarati', kn: 'Kannada', ml: 'Malayalam',
  pa: 'Punjabi', ur: 'Urdu', or: 'Odia', as: 'Assamese', ne: 'Nepali', en: 'English', es: 'Spanish', fr: 'French', de: 'German',
  pt: 'Portuguese', it: 'Italian', ja: 'Japanese', ko: 'Korean', zh: 'Chinese', ar: 'Arabic', ru: 'Russian', id: 'Indonesian' };

export function translatePrompt(text, lang) {
  const name = LANGS[String(lang).toLowerCase()] || lang;
  return `Translate the text between the markers into ${name}. Keep the meaning, tone, names, numbers and line breaks. ` +
    `Reply with the translation only, no notes and no quotes.\n<<<\n${text}\n>>>`;
}

async function call(path, body, timeoutSec) {
  const base = ollamaBase();
  let res;
  try {
    res = await fetch(base + path, {
      method: body ? 'POST' : 'GET',
      headers: body ? { 'content-type': 'application/json' } : undefined,
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(timeoutSec * 1000),
    });
  } catch (e) {
    throw new Error(`cannot reach Ollama at ${base} (${e.cause?.code || e.name}); start it or set OLLAMA_HOST`);
  }
  const text = await res.text();
  let j = {};
  try { j = JSON.parse(text); } catch {}
  if (!res.ok) throw new Error(`Ollama ${res.status}: ${j.error || text.slice(0, 200)}`);
  return j;
}

export async function generate(model, prompt, { timeout = 300 } = {}) {
  const j = await call('/api/generate', { model, prompt, stream: false }, timeout);
  if (typeof j.response !== 'string') throw new Error('Ollama sent no response text');
  return j.response.trim();
}

// Runs fn over items with at most `limit` in flight; results land at their input index.
export async function pool(items, limit, fn) {
  const out = new Array(items.length);
  let next = 0;
  const worker = async () => { for (;;) { const i = next++; if (i >= items.length) return; out[i] = await fn(items[i], i); } };
  await Promise.all(Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, worker));
  return out;
}

function parseArgs(argv) {
  const pos = [], opt = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) opt[argv[i].slice(2)] = argv[++i];
    else pos.push(argv[i]);
  }
  return { pos, opt };
}

async function main(argv) {
  const [cmd, ...rest] = argv;
  const { pos, opt } = parseArgs(rest);
  const usage = () => {
    console.error('usage: kaito-ollama.mjs run <model> [--translate-to <lang>] [--timeout <sec>] < prompt\n' +
      '       kaito-ollama.mjs bulk <model> <prompts.jsonl> [--out <file>] [--concurrency <n>] [--translate-to <lang>] [--timeout <sec>]\n' +
      '       kaito-ollama.mjs tags');
    process.exit(2);
  };
  const timeout = opt.timeout === undefined ? 300 : Number(opt.timeout);
  const wrap = (t) => (opt['translate-to'] ? translatePrompt(t, opt['translate-to']) : t);
  if (!(timeout > 0) || ('translate-to' in opt && !opt['translate-to'])) usage();
  try {
    if (cmd === 'tags' && !pos.length) {
      console.log(JSON.stringify((await call('/api/tags', null, 10)).models || [], null, 2));
    } else if (cmd === 'run' && pos.length === 1) {
      const input = readFileSync(0, 'utf8');
      if (!input.trim()) { console.error('no prompt on stdin'); process.exit(2); }
      console.log(await generate(pos[0], wrap(input.replace(/\n$/, '')), { timeout }));
    } else if (cmd === 'bulk' && pos.length === 2) {
      const n = opt.concurrency === undefined ? 2 : Number(opt.concurrency);
      if (!Number.isInteger(n) || n < 1) usage();
      // i is the line number in the file (from 0), blank lines included, so a result points at its source line.
      const rows = readFileSync(pos[1], 'utf8').split(/\r?\n/).map((l, i) => [l, i]).filter(([l]) => l.trim()).map(([l, i]) => {
        let v;
        try { v = JSON.parse(l); } catch { return { i, bad: `line ${i + 1} is not JSON` }; }
        const prompt = typeof v === 'string' ? v : v && typeof v.prompt === 'string' ? v.prompt : null;
        return prompt === null ? { i, bad: `line ${i + 1} has no prompt` } : { i, id: v.id, prompt };
      });
      let failed = 0;
      const lines = await pool(rows, n, async (r) => {
        const base = r.id === undefined ? { i: r.i } : { i: r.i, id: r.id };
        try {
          if (r.bad) throw new Error(r.bad);
          return JSON.stringify({ ...base, text: await generate(pos[0], wrap(r.prompt), { timeout }) });
        } catch (e) { failed++; return JSON.stringify({ ...base, error: e.message }); }
      });
      const text = lines.length ? lines.join('\n') + '\n' : '';
      if (opt.out) writeFileSync(opt.out, text); else process.stdout.write(text);
      if (failed) { console.error(`${failed} of ${rows.length} prompts failed`); process.exitCode = 1; }
    } else usage();
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}

let isMain = false;
try { isMain = realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); } catch {}
if (isMain) await main(process.argv.slice(2));
