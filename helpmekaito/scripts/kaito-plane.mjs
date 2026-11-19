// Tiny Plane REST client (API v1). Import only: plane(method, path, body), all(path), redact(s).
// The key comes from env KAITO_PLANE_KEY, never argv, and goes out in the X-API-Key header.
// Base URL: KAITO_PLANE_API, else KAITO_PLANE_BASE + /api/v1 (self-hosted), else https://api.plane.so/api/v1.
// Paths are relative to the workspace: /projects/ becomes /workspaces/<slug>/projects/. /users/me/ is not.
const redact = (s) => {
  let out = String(s);
  const v = process.env.KAITO_PLANE_KEY;
  if (v) out = out.split(v).join('REDACTED');
  return out;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
export const base = () => (process.env.KAITO_PLANE_API
  || `${(process.env.KAITO_PLANE_BASE || 'https://api.plane.so').replace(/\/+$/, '')}/api/v1`).replace(/\/+$/, '');

export async function plane(method, path, body) {
  method = method.toUpperCase();
  const key = process.env.KAITO_PLANE_KEY, ws = process.env.KAITO_PLANE_WORKSPACE;
  if (!key) throw new Error('plane: no credentials');
  const scoped = !path.startsWith('/users/');
  if (scoped && !/^[A-Za-z0-9_-]+$/.test(ws || '')) throw new Error('plane: no workspace');
  const url = base() + (scoped ? `/workspaces/${ws}` : '') + path;
  const tries = method === 'GET' ? 2 : 1;  // writes never auto-retry: a lost reply must not double a create
  for (let i = 0; ; i++) {
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), 10000);
    let status;
    try {
      const res = await fetch(url, {
        method,
        headers: { 'x-api-key': key, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
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
    throw new Error(redact(`plane ${status} ${method} ${path.split('?')[0]}`));
  }
}

// Every page of a list. Plane answers with { results, next_cursor, next_page_results } or, on a few endpoints, a bare array.
// ponytail: gives up after 30 pages (3000 rows) with code TOO_MANY, never a partial list; a bigger project needs a module mapping.
export async function all(path) {
  const out = [];
  let cursor = '';
  const max = Number(process.env.KAITO_PLANE_PAGES) || 30;
  for (let page = 0; page < max; page++) {
    const r = await plane('GET', `${path}${path.includes('?') ? '&' : '?'}per_page=100${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`);
    if (Array.isArray(r)) return r.flat(Infinity);
    out.push(...(r.results || []));
    if (!r.next_page_results || !r.next_cursor) return out;
    cursor = r.next_cursor;
  }
  throw Object.assign(new Error(`plane: more than ${max * 100} rows at ${path.split('?')[0]}`), { code: 'TOO_MANY' });
}
export { redact };
