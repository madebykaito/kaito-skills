// Fake Plane REST API v1, in memory. node plane-api.mjs <log-file> <port-file>
// Every request is logged as one JSON line: method, path (workspace prefix kept), query, creds (key header present), body.
// Env knobs:
//   STUB_FAIL="METHOD /path-prefix STATUS COUNT;..."  fail matching requests COUNT times with STATUS
//   STUB_AUTH="key"       only this key is accepted, anything else gets 401
//   STUB_NODONE=1         project ALL has no completed state
//   STUB_PAGE=<n>         page size for list endpoints (default 100), to exercise cursors
import { createServer } from 'node:http';
import { writeFileSync, appendFileSync } from 'node:fs';

const [logFile, portFile] = process.argv.slice(2);
const fails = (process.env.STUB_FAIL || '').split(';').filter(Boolean).map((s) => {
  const [method, prefix, status, count] = s.trim().split(/\s+/);
  return { method, prefix, status: Number(status), left: Number(count || 1) };
});
let n = 0;
const uuid = () => `00000000-0000-4000-8000-${(++n).toString(16).padStart(12, '0')}`;
export const P1 = '11111111-1111-4111-8111-111111111111', P2 = '22222222-2222-4222-8222-222222222222', MOD = '33333333-3333-4333-8333-333333333333';

const me = { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', display_name: 'kaito', email: 'k@example.test' };
const projects = [
  { id: P1, name: 'ALL', identifier: 'ALL', archived_at: null },
  { id: P2, name: 'Personal', identifier: 'PER', archived_at: null },
];
const states = [
  { id: 's-backlog', project: P1, name: 'Backlog', group: 'backlog', sequence: 10000 },
  { id: 's-todo', project: P1, name: 'To Do', group: 'unstarted', sequence: 20000 },
  { id: 's-doing', project: P1, name: 'In Progress', group: 'started', sequence: 30000 },
  { id: 's-cancel', project: P1, name: 'Cancelled', group: 'cancelled', sequence: 60000 },
  { id: 's-ptodo', project: P2, name: 'Todo', group: 'unstarted', sequence: 1 },
];
if (!process.env.STUB_NODONE) states.push({ id: 's-done', project: P1, name: 'Done', group: 'completed', sequence: 50000 });
const labels = [{ id: 'lb-bug', project: P1, name: 'bug', color: '#f00' }, { id: 'lb-ui', project: P1, name: 'ui', color: '#00f' }];
const modules = [{ id: MOD, project: P1, name: 'Kaito Skills', archived_at: null }];
const members = { [P1]: [me, { id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', display_name: 'other' }], [P2]: [] };
const items = [], inModule = new Set(), comments = [], links = [];
const seq = {};
const addItem = (o) => {
  const project = o.project || P1;
  seq[project] = (seq[project] || 0) + 1;
  const w = { id: uuid(), project, sequence_id: seq[project], name: '', description_html: '', description_stripped: '', state: project === P1 ? 's-backlog' : 's-ptodo',
    parent: null, labels: [], assignees: [], target_date: null, priority: 'none', archived_at: null, is_draft: false, ...o };
  items.push(w);
  return w;
};
const w1 = addItem({ name: 'Add Plane support', description_html: '<p>private words alpha</p>', description_stripped: 'private words alpha',
  state: 's-todo', labels: ['lb-bug'], target_date: '2026-12-01' });                       // ALL-1, in the module
addItem({ name: 'Write the client', parent: w1.id, state: 's-todo' });                      // ALL-2, child
addItem({ name: 'Write the tests', parent: w1.id, state: 's-done' });                       // ALL-3, child, done
const w4 = addItem({ name: 'Migrate to Plane', state: 's-doing' });                         // ALL-4, in the module
addItem({ name: 'Company admin', state: 's-todo' });                                        // ALL-5, not in the module
addItem({ name: 'Old shipped thing', state: 's-done' });                                    // ALL-6, closed
addItem({ name: 'Buy milk', project: P2 });                                                 // PER-1
for (const w of [w1, w4]) inModule.add(w.id);

const page = (rows, q) => {
  const size = Math.min(Number(q.get('per_page')) || 100, Number(process.env.STUB_PAGE) || 100);
  const off = Number((q.get('cursor') || '').split(':')[1] || 0);
  const next = (off + 1) * size < rows.length;
  return { results: rows.slice(off * size, (off + 1) * size), next_cursor: `${size}:${off + 1}:0`, prev_cursor: '', next_page_results: next, prev_page_results: off > 0,
    count: Math.min(size, rows.length), total_pages: Math.ceil(rows.length / size), total_results: rows.length };
};
const patch = (w, body) => { for (const k of ['name', 'state', 'parent', 'description_html', 'target_date', 'priority', 'assignees', 'labels']) if (body[k] !== undefined) w[k] = body[k]; return w; };

function route(method, path, q, body) {
  if (method === 'GET' && path === '/users/me/') return me;
  const m = path.match(/^\/workspaces\/([^/]+)(\/.*)$/);
  if (!m) return 404;
  if (m[1] !== 'acme') return 403;
  const p = m[2].split('/').filter(Boolean);
  if (p[0] === 'work-items' && method === 'GET' && p.length === 2) {
    const x = p[1].match(/^([A-Za-z0-9]+)-(\d+)$/);
    const pr = x && projects.find((r) => r.identifier === x[1].toUpperCase());
    return (pr && items.find((w) => w.project === pr.id && w.sequence_id === Number(x[2]))) || 404;
  }
  if (p[0] !== 'projects') return 404;
  if (p.length === 1) return method === 'GET' ? page(projects, q) : 404;
  const pr = projects.find((r) => r.id === p[1]);
  if (!pr) return 404;
  const of = (xs) => xs.filter((r) => r.project === pr.id);
  if (method === 'GET' && p.length === 3) {
    if (p[2] === 'states') return page(of(states), q);
    if (p[2] === 'labels') return page(of(labels), q);
    if (p[2] === 'modules') return page(of(modules), q);
    if (p[2] === 'project-members') return [members[pr.id] || []];  // the docs show a nested array
    if (p[2] === 'work-items') return page(of(items), q);
  }
  if (p[2] === 'modules' && p[4] === 'module-issues') {
    if (!modules.find((x) => x.id === p[3])) return 404;
    if (method === 'GET') return page(items.filter((w) => inModule.has(w.id)), q);
    if (method === 'POST') { for (const id of body.issues || []) inModule.add(id); return (body.issues || []).map((id) => ({ id: uuid(), module: p[3], issue: id })); }
  }
  if (p[2] === 'work-items') {
    if (method === 'POST' && p.length === 3) {
      if (!body.name) return 400;
      if (body.state && !of(states).find((s) => s.id === body.state)) return 400;
      return [201, addItem({ project: pr.id, ...patch({}, body) })];
    }
    const w = of(items).find((x) => x.id === p[3]);
    if (!w) return 404;
    if (p.length === 4 && method === 'GET') return w;
    if (p.length === 4 && method === 'PATCH') {
      if (body.state && !of(states).find((s) => s.id === body.state)) return 400;
      return patch(w, body);
    }
    if (p[4] === 'comments' && method === 'POST') { const c = { id: uuid(), issue: w.id, comment_html: body.comment_html }; comments.push(c); return [201, c]; }
    if (p[4] === 'links' && method === 'GET') return page(links.filter((x) => x.issue === w.id), q);
    if (p[4] === 'links' && method === 'POST') { if (!body.url || links.some((x) => x.issue === w.id && x.url === body.url)) return 400; const l = { id: uuid(), issue: w.id, url: body.url, title: body.title ?? '' }; links.push(l); return [201, l]; }
  }
  return 404;
}

createServer((req, res) => {
  let raw = '';
  req.on('data', (c) => (raw += c));
  req.on('end', () => {
    const u = new URL(req.url, 'http://x');
    const path = u.pathname.replace(/^\/api\/v1(?=\/)/, '');
    const key = req.headers['x-api-key'];
    let body = {};
    try { if (raw) body = JSON.parse(raw); } catch { body = { raw }; }
    appendFileSync(logFile, JSON.stringify({ method: req.method, path, query: Object.fromEntries(u.searchParams), creds: !!key, body }) + '\n');
    const send = (status, obj) => {
      res.statusCode = status;
      if (status === 429) res.setHeader("retry-after", "1");
      res.setHeader('content-type', 'application/json');
      res.end(obj === undefined ? `{"detail":"error ${status}"}` : JSON.stringify(obj));
    };
    const f = fails.find((x) => x.left > 0 && x.method === req.method && path.startsWith(x.prefix));
    if (f) { f.left--; return send(f.status); }
    if (!key) return send(401);
    if (process.env.STUB_AUTH && process.env.STUB_AUTH !== key) return send(401);
    const out = route(req.method, path, u.searchParams, body);
    if (typeof out === 'number') return send(out);
    if (Array.isArray(out) && typeof out[0] === 'number') return send(out[0], out[1]);
    send(200, out);
  });
}).listen(0, '127.0.0.1', function () { writeFileSync(portFile, String(this.address().port)); });
