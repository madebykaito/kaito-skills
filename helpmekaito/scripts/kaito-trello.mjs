// Tiny Trello REST wrapper: node kaito-trello.mjs <METHOD> <path> [json-body]
// Key and token come from env KAITO_TRELLO_KEY / KAITO_TRELLO_TOKEN only, never argv.
// Base URL from KAITO_TRELLO_API (default https://api.trello.com/1). Also importable: trello(method, path, body).
import { pathToFileURL } from 'node:url';

const redact = (s) => {
  let out = String(s);
  for (const v of [process.env.KAITO_TRELLO_KEY, process.env.KAITO_TRELLO_TOKEN]) {
    if (v) out = out.split(v).join('REDACTED');
  }
  return out.replace(/([?&](key|token)=)[^&\s]*/gi, '$1REDACTED');
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function trello(method, path, body) {
  method = method.toUpperCase();
  const key = process.env.KAITO_TRELLO_KEY, token = process.env.KAITO_TRELLO_TOKEN;
  if (!key || !token) throw new Error('trello: no credentials');
  const base = (process.env.KAITO_TRELLO_API || 'https://api.trello.com/1').replace(/\/+$/, '');
  const url = new URL(base + (path.startsWith('/') ? path : '/' + path));
  url.searchParams.set('key', key);
  url.searchParams.set('token', token);
  const tries = method === 'GET' ? 2 : 1;  // writes never auto-retry: a lost reply must not double a create
  for (let i = 0; ; i++) {
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), 10000);
    let status;
    try {
      const res = await fetch(url, {
        method,
        headers: body === undefined ? {} : { 'content-type': 'application/json' },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: ac.signal,
      });
      status = res.status;
      const text = await res.text();
      if (res.ok) return text ? JSON.parse(text) : {};
    } catch (e) {
      status = status ?? (e.name === 'AbortError' ? 'timeout' : 'network');
    } finally {
      clearTimeout(timer);
    }
    const again = typeof status === 'number' && (status === 429 || status >= 500);
    if (again && i + 1 < tries) { await sleep(500); continue; }
    throw new Error(redact(`trello ${status} ${method} ${path}`));
  }
}
export { redact };

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [method, arg, raw] = process.argv.slice(2);
  // Git Bash rewrites a /path argument to C:/Program Files/Git/path before node sees it. Undo that.
  // shortcut: keys on the first Trello resource name in the path; fine unless Git's install folder contains one.
  const m = /^[A-Za-z]:[\\/]/.test(arg || '') &&
    /[\\/](?:1[\\/])?(?:members|cards|boards|lists|checklists|labels|actions|search|organizations|customFields?|tokens|webhooks|notifications|batch)(?=[\\/?]|$)/.exec(arg);
  const path = m ? arg.slice(m.index).replace(/\\/g, '/') : arg;
  if (!method || !path) {
    console.error('usage: node kaito-trello.mjs <METHOD> <path> [json-body]');
    process.exit(2);
  }
  try {
    const out = await trello(method, path, raw === undefined ? undefined : JSON.parse(raw));
    console.log(JSON.stringify(out));
  } catch (e) {
    console.error(redact(e.message));
    process.exit(1);
  }
}
