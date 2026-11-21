// Tiny Linear GraphQL client. Import only: linear(query, vars), all(query, vars, pick), redact(s).
// The key comes from env KAITO_LINEAR_KEY, never argv, and goes out in the Authorization header (a personal key, no "Bearer").
// Endpoint: KAITO_LINEAR_API, else https://api.linear.app/graphql.
const redact = (s) => {
  let out = String(s);
  const v = process.env.KAITO_LINEAR_KEY;
  if (v) out = out.split(v).join('REDACTED');
  return out;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
export const base = () => (process.env.KAITO_LINEAR_API || 'https://api.linear.app/graphql').replace(/\/+$/, '');
export const PAGE = 50;  // Linear's default page; a bigger one multiplies the query's complexity score

// Every query and mutation is named, so errors and the test log can say which one it was.
export async function linear(query, vars = {}) {
  const key = process.env.KAITO_LINEAR_KEY;
  if (!key) throw new Error('linear: no credentials');
  const [, kind = 'query', name = 'anonymous'] = query.match(/^\s*(query|mutation)\s+(\w+)/) || [];
  const tries = kind === 'query' ? 2 : 1;  // writes never auto-retry: a lost reply must not double a create
  for (let i = 0; ; i++) {
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), 10000);
    let status, wait = 500, why = '', code;
    try {
      const res = await fetch(base(), {
        method: 'POST',
        headers: { authorization: key, 'content-type': 'application/json' },
        body: JSON.stringify({ query, variables: vars }),
        signal: ac.signal,
      });
      status = res.status;
      const text = await res.text();
      let json = {};
      try { json = text ? JSON.parse(text) : {}; } catch {}
      const err = json.errors?.[0];
      if (res.ok && !err && json.data) return json.data;
      if (err) { why = `: ${String(err.message || '').replace(/[\r\n]+/g, ' ').slice(0, 200)}`; code = err.extensions?.code; }
      // Linear can send a rate limit as a 400 with code RATELIMITED: it is a 429 whatever the HTTP status.
      if (code === 'RATELIMITED') status = 429;
      else if (res.ok) status = 'error';
      // A 429 says when to come back: Retry-After in seconds. Wait that long, a minute at most.
      const ra = Number(res.headers.get('retry-after'));
      if (status === 429 && ra > 0) wait = Math.min(Math.max(ra * 1000, 500), 60000);
    } catch (e) {
      status = status ?? (e.name === 'AbortError' ? 'timeout' : 'network');
    } finally {
      clearTimeout(timer);
    }
    const again = typeof status === 'number' && (status === 429 || status >= 500);
    if (again && i + 1 < tries) { await sleep(wait); continue; }
    throw Object.assign(new Error(redact(`linear ${status} ${name}${why}`)), { code });
  }
}

// Every page of one connection. The query takes $first and $after; pick(data) returns the connection ({ nodes, pageInfo }).
// ponytail: gives up after 40 pages (2000 rows) with code TOO_MANY, never a partial list; a bigger team needs a project mapping.
export async function all(query, vars, pick) {
  const out = [];
  let after = null;
  const max = Number(process.env.KAITO_LINEAR_PAGES) || 40;
  for (let page = 0; page < max; page++) {
    const c = pick(await linear(query, { ...vars, first: PAGE, after })) || {};
    out.push(...(c.nodes || []));
    if (!c.pageInfo?.hasNextPage || !c.pageInfo.endCursor) return out;
    after = c.pageInfo.endCursor;
  }
  throw Object.assign(new Error(`linear: more than ${max * PAGE} rows`), { code: 'TOO_MANY' });
}
export { redact };
