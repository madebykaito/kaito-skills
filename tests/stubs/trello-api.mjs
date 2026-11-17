// Fake Trello REST API, in memory. node trello-api.mjs <log-file> <port-file>
// Every request is logged as one JSON line: method, path, query (key/token left out), creds (both present).
// Env knobs:
//   STUB_FAIL="METHOD /path-prefix STATUS COUNT;..."  fail matching requests COUNT times with STATUS
//   STUB_AUTH="key:token"  only this pair is accepted, anything else gets 401
//   STUB_NODONE=1          board b1 has no Done list
//   STUB_PS=1              log ps_leak: true if the token shows in any process argv
import { createServer } from 'node:http';
import { writeFileSync, appendFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const [logFile, portFile] = process.argv.slice(2);
const fails = (process.env.STUB_FAIL || '').split(';').filter(Boolean).map((s) => {
  const [method, prefix, status, count] = s.trim().split(/\s+/);
  return { method, prefix, status: Number(status), left: Number(count || 1) };
});
let n = 0;
const hex = () => (++n).toString(16).padStart(24, 'a');
const short = () => ('S' + (++n).toString(36)).padEnd(8, 'x');

const me = { id: 'm1', username: 'kaito', fullName: 'Kaito Junior' };
const boards = [
  { id: 'b1', name: 'Work', closed: false },
  { id: 'b2', name: 'Home', closed: false },
  { id: 'b3', name: 'Old', closed: true },
];
const lists = [
  { id: 'l1', idBoard: 'b1', name: 'To Do', pos: 1, closed: false },
  { id: 'l2', idBoard: 'b1', name: 'Doing', pos: 2, closed: false },
  { id: 'l4', idBoard: 'b2', name: 'Inbox', pos: 1, closed: false },
];
if (!process.env.STUB_NODONE) lists.push({ id: 'l3', idBoard: 'b1', name: 'Done', pos: 3, closed: false });
const labels = [
  { id: 'lb1', idBoard: 'b1', name: 'bug', color: 'red' },
  { id: 'lb2', idBoard: 'b1', name: 'ui', color: 'blue' },
];
const customFields = [
  { id: 'cf1', idModel: 'b1', name: 'Ref', type: 'text' },
  { id: 'cf2', idModel: 'b1', name: 'Priority', type: 'list',
    options: [{ id: 'o1', value: { text: 'High' } }, { id: 'o2', value: { text: 'Low' } }] },
];
const members = { b1: [me, { id: 'm2', username: 'other', fullName: 'Other Person' }], b2: [me] };
const cards = [];
const checklists = [];
const actions = [];
const addCard = (o) => {
  const c = { id: hex(), shortLink: short(), idBoard: 'b1', idList: 'l1', name: '', desc: '', due: null, start: null,
    closed: false, idLabels: [], idChecklists: [], idMembers: [], customFieldItems: [], ...o };
  cards.push(c);
  return c;
};
const addChecklist = (card, name, items = []) => {
  const cl = { id: hex(), idCard: card.id, name, checkItems: items.map((t, i) => ({ id: hex(), name: t, state: 'incomplete', pos: i + 1 })) };
  checklists.push(cl);
  card.idChecklists.push(cl.id);
  return cl;
};
const c1 = addCard({ name: '[HI] Fix login', desc: 'private words alpha', idLabels: ['lb1'], due: '2026-12-01T09:00:00.000Z',
  customFieldItems: [{ idCustomField: 'cf1', value: { text: 'R-1' } }] });
addChecklist(c1, 'Steps', ['write test', 'fix it']);
addCard({ name: '[HI] Same title', desc: 'private words beta', idList: 'l2' });
addCard({ name: '[HI] Same title', desc: '', idList: 'l2' });
addCard({ name: 'Plain card', idBoard: 'b2', idList: 'l4' });

const findCard = (id) => cards.find((c) => c.id === id || c.shortLink === id);
const view = (c, q) => {
  const out = { ...c, url: `https://trello.example/c/${c.shortLink}`,
    labels: labels.filter((l) => c.idLabels.includes(l.id)).map(({ id, name, color }) => ({ id, name, color })) };
  if (q.get('checklists') === 'all') out.checklists = checklists.filter((cl) => cl.idCard === c.id);
  return out;
};

function route(method, path, q, body) {
  const p = path.split('/').filter(Boolean);
  const arg = (k) => body[k] ?? q.get(k) ?? undefined;
  if (method === 'GET' && path === '/members/me') return me;
  if (method === 'GET' && path === '/members/me/boards') return boards.filter((b) => !b.closed).map(({ id, name }) => ({ id, name }));
  if (p[0] === 'boards' && method === 'GET') {
    const b = boards.find((x) => x.id === p[1]);
    if (!b) return 404;
    if (p.length === 2) return { id: b.id, name: b.name, closed: b.closed };
    if (p[2] === 'lists') return lists.filter((l) => l.idBoard === b.id && !l.closed);
    if (p[2] === 'labels') return labels.filter((l) => l.idBoard === b.id);
    if (p[2] === 'customFields') return customFields.filter((f) => f.idModel === b.id);
    if (p[2] === 'members') return (members[b.id] || []).map(({ id, username, fullName }) => ({ id, username, fullName }));
    if (p[2] === 'cards') {
      let cs = cards.filter((c) => c.idBoard === b.id && (p[3] === 'all' || !c.closed));
      if (q.get('limit')) cs = cs.slice(-Number(q.get('limit')));
      return cs.map((c) => view(c, q));
    }
    return 404;
  }
  if (p[0] === 'cards') {
    if (method === 'POST' && p.length === 1) {
      const list = lists.find((l) => l.id === arg('idList'));
      if (!list) return 400;
      const idMembers = arg('idMembers');
      return view(addCard({ name: arg('name') || '', desc: arg('desc') || '', due: arg('due') || null, idList: list.id, idBoard: list.idBoard,
        idMembers: Array.isArray(idMembers) ? idMembers : idMembers ? String(idMembers).split(',') : [] }), q);
    }
    const c = findCard(p[1]);
    if (!c) return 404;
    if (method === 'GET' && p.length === 2) return view(c, q);
    if (method === 'GET' && p[2] === 'checklists') return checklists.filter((cl) => cl.idCard === c.id);
    if (method === 'PUT' && p.length === 2) {
      for (const k of ['name', 'desc', 'due', 'idList', 'closed']) {
        const v = arg(k);
        if (v !== undefined) c[k] = k === 'closed' ? v === true || v === 'true' : v;
      }
      return view(c, q);
    }
    if (method === 'POST' && p[2] === 'checklists') return addChecklist(c, arg('name') || 'Checklist');
    if (method === 'PUT' && p[2] === 'checkItem') {
      const it = checklists.filter((cl) => cl.idCard === c.id).flatMap((cl) => cl.checkItems).find((i) => i.id === p[3]);
      if (!it) return 404;
      if (arg('state')) it.state = arg('state');
      if (arg('name')) it.name = arg('name');
      return it;
    }
    if (method === 'POST' && p[2] === 'actions' && p[3] === 'comments') {
      const a = { id: hex(), type: 'commentCard', data: { text: arg('text'), card: { id: c.id } } };
      actions.push(a);
      return a;
    }
    return 404;
  }
  if (p[0] === 'checklists' && method === 'POST' && p[2] === 'checkItems') {
    const cl = checklists.find((x) => x.id === p[1]);
    if (!cl) return 404;
    const it = { id: hex(), name: arg('name'), state: 'incomplete', pos: cl.checkItems.length + 1 };
    cl.checkItems.push(it);
    return it;
  }
  return 404;
}

createServer((req, res) => {
  let raw = '';
  req.on('data', (c) => (raw += c));
  req.on('end', () => {
    const u = new URL(req.url, 'http://x');
    const path = u.pathname.replace(/^\/1(?=\/)/, '');
    const key = u.searchParams.get('key'), token = u.searchParams.get('token');
    const query = Object.fromEntries([...u.searchParams].filter(([k]) => k !== 'key' && k !== 'token'));
    let body = {};
    try { if (raw) body = JSON.parse(raw); } catch { body = { raw }; }
    const entry = { method: req.method, path, query, creds: !!(key && token), body };
    if (process.env.STUB_PS && token) {
      const ps = execFileSync('ps', ['-Ao', 'args'], { encoding: 'utf8' });
      entry.ps_leak = ps.split('\n').some((l) => l.includes(token));
    }
    appendFileSync(logFile, JSON.stringify(entry) + '\n');
    const send = (status, obj) => {
      res.statusCode = status;
      res.setHeader('content-type', 'application/json');
      res.end(obj === undefined ? `{"message":"error ${status}"}` : JSON.stringify(obj));
    };
    const f = fails.find((x) => x.left > 0 && x.method === req.method && path.startsWith(x.prefix));
    if (f) { f.left--; return send(f.status); }
    if (!key || !token) return send(401);
    if (process.env.STUB_AUTH && process.env.STUB_AUTH !== `${key}:${token}`) return send(401);
    const out = route(req.method, path, u.searchParams, body);
    if (typeof out === 'number') return send(out);
    send(200, out);
  });
}).listen(0, '127.0.0.1', function () { writeFileSync(portFile, String(this.address().port)); });
