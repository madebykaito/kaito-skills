// Fake Linear GraphQL API, in memory. node linear-api.mjs <log-file> <port-file>
// No GraphQL engine: the operation name in the query text picks the handler, which reads the variables
// and returns whole objects shaped like the real API. Every request is logged as one JSON line: op, kind, vars, creds.
// Env knobs:
//   STUB_FAIL="OpName STATUS COUNT;..."  fail that operation COUNT times with STATUS (a 429 says retry-after: 1);
//                         STATUS RATELIMITED is Linear's other form: HTTP 400, code RATELIMITED, retry-after: 1
//   STUB_AUTH="key"       only this key is accepted, anything else gets 401
//   STUB_NODONE=1         team KAI has no completed state
//   STUB_PAGE=<n>         caps variables.first, to exercise cursors
//   STUB_KIDS=<n>         the children inline on Issues and Issue return only n nodes (hasNextPage true)
import { createServer } from 'node:http';
import { writeFileSync, appendFileSync } from 'node:fs';

const [logFile, portFile] = process.argv.slice(2);
const fails = (process.env.STUB_FAIL || '').split(';').filter(Boolean).map((s) => {
  const [op, status, count] = s.trim().split(/\s+/);
  return { op, status: status === 'RATELIMITED' ? status : Number(status), left: Number(count || 1) };
});
let n = 0;
const uuid = () => `00000000-0000-4000-8000-${(++n).toString(16).padStart(12, '0')}`;
export const T1 = '11111111-1111-4111-8111-111111111111', T2 = '22222222-2222-4222-8222-222222222222';
export const PJ = '33333333-3333-4333-8333-333333333333', PJDONE = '44444444-4444-4444-8444-444444444444';

const me = { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', name: 'Kaito Junior', displayName: 'kaito' };
const other = { id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', name: 'Other Person', displayName: 'other' };
const organization = { name: 'Acme', urlKey: 'acme' };
const teams = [{ id: T1, key: 'KAI', name: 'Kaito' }, { id: T2, key: 'PER', name: 'Personal' }];
const states = [
  { id: 's-backlog', team: T1, name: 'Backlog', type: 'backlog', position: 0 },
  { id: 's-todo', team: T1, name: 'To Do', type: 'unstarted', position: 1 },
  { id: 's-doing', team: T1, name: 'In Progress', type: 'started', position: 2 },
  { id: 's-cancel', team: T1, name: 'Cancelled', type: 'canceled', position: 4 },
  { id: 's-ptodo', team: T2, name: 'Todo', type: 'unstarted', position: 0 },
  { id: 's-pdone', team: T2, name: 'Done', type: 'completed', position: 1 },
];
if (!process.env.STUB_NODONE) states.push({ id: 's-done', team: T1, name: 'Done', type: 'completed', position: 3 });
const projects = [
  { id: PJ, team: T1, name: 'Kaito Skills', status: { type: 'started' } },
  { id: PJDONE, team: T1, name: 'Shipped Project', status: { type: 'completed' } },
];
const labels = [{ id: 'lb-bug', team: T1, name: 'bug', color: '#f00' }, { id: 'lb-ui', team: T1, name: 'ui', color: '#00f' }];
const members = { [T1]: [me, other], [T2]: [me] };
const issues = [], comments = [], attachments = [];
const seq = {};
const keyOf = (w) => `${teams.find((t) => t.id === w.team).key}-${w.number}`;
const addIssue = (o) => {
  const team = o.team || T1;
  seq[team] = (seq[team] || 0) + 1;
  const w = { id: uuid(), team, number: seq[team], title: '', description: null, dueDate: null, priority: 0,
    archivedAt: null, state: team === T1 ? 's-backlog' : 's-ptodo', labels: [], project: null, parent: null, assignee: null, ...o };
  issues.push(w);
  return w;
};
const k1 = addIssue({ title: 'Add Linear support', description: 'private words alpha', state: 's-todo', labels: ['lb-bug'],
  dueDate: '2026-12-01', project: PJ });                                                           // KAI-1, in the project
addIssue({ title: 'Write the client', parent: k1.id, state: 's-todo' });                          // KAI-2, child
addIssue({ title: 'Write the tests', parent: k1.id, state: 's-done' });                           // KAI-3, child, done
addIssue({ title: 'Migrate to Linear', state: 's-doing', project: PJ });                          // KAI-4, in the project
addIssue({ title: 'Company admin', state: 's-todo' });                                            // KAI-5, no project
addIssue({ title: 'Old shipped thing', state: 's-done' });                                        // KAI-6, closed
addIssue({ title: 'Archived idea', state: 's-todo', archivedAt: '2026-01-01T00:00:00.000Z' });    // KAI-7, archived
addIssue({ title: 'Buy milk', team: T2 });                                                        // PER-1

const NOT_FOUND = (what) => ({ errors: [{ message: `Entity not found: ${what}`, extensions: { code: 'INPUT_ERROR' } }] });
const bad = (m) => ({ errors: [{ message: m, extensions: { code: 'INPUT_ERROR' } }] });
// Archived rows are hidden, as the real API does without includeArchived.
const live = (xs) => xs.filter((w) => !w.archivedAt);
const conn = (rows, first, after) => {
  const cap = Number(process.env.STUB_PAGE) || Infinity;
  const size = Math.min(Number(first) || 50, cap);
  const off = Number(after || 0);
  const nodes = rows.slice(off, off + size);
  return { nodes, pageInfo: { hasNextPage: off + size < rows.length, endCursor: nodes.length ? String(off + size) : null } };
};
const stateOf = (id) => { const s = states.find((x) => x.id === id); return s ? { id: s.id, name: s.name, type: s.type } : null; };
const kid = (w) => ({ id: w.id, identifier: keyOf(w), title: w.title, archivedAt: w.archivedAt, state: { type: stateOf(w.state)?.type } });
const kidsOf = (w) => live(issues.filter((x) => x.parent === w.id));
function issueOut(w) {
  const p = w.parent && issues.find((x) => x.id === w.parent);
  const ks = kidsOf(w), cap = Number(process.env.STUB_KIDS) || Infinity;
  const ident = keyOf(w);
  return {
    id: w.id, identifier: ident, title: w.title, description: w.description, dueDate: w.dueDate, priority: w.priority,
    url: `https://linear.app/${organization.urlKey}/issue/${ident}/${w.title.toLowerCase().replace(/[^a-z0-9]+/g, '-')}`,
    archivedAt: w.archivedAt, state: stateOf(w.state),
    labels: { nodes: labels.filter((l) => w.labels.includes(l.id)).map((l) => ({ id: l.id, name: l.name })) },
    team: { id: w.team }, project: w.project ? { id: w.project } : null,
    parent: p ? { id: p.id, identifier: keyOf(p), project: p.project ? { id: p.project } : null } : null,
    children: { nodes: ks.slice(0, cap).map(kid), pageInfo: { hasNextPage: ks.length > cap, endCursor: null } },
  };
}
const findIssue = (id) => issues.find((w) => w.id === id || keyOf(w) === String(id).toUpperCase());
const findTeam = (id) => teams.find((t) => t.id === id);
function matches(w, f = {}) {
  if (f.team?.id?.eq && w.team !== f.team.id.eq) return false;
  if (f.project?.id?.eq && w.project !== f.project.id.eq) return false;
  if (f.state?.type?.nin && f.state.type.nin.includes(stateOf(w.state)?.type)) return false;
  return true;
}
function setFields(w, input) {
  for (const k of ['title', 'description', 'dueDate', 'priority']) if (input[k] !== undefined) w[k] = input[k];
  if (input.stateId !== undefined) w.state = input.stateId;
  if (input.projectId !== undefined) w.project = input.projectId;
  if (input.parentId !== undefined) w.parent = input.parentId;
  if (input.assigneeId !== undefined) w.assignee = input.assigneeId;
  if (input.labelIds !== undefined) w.labels = input.labelIds;
}
const badState = (team, id) => id !== undefined && !states.some((s) => s.id === id && s.team === team);

const ops = {
  Viewer: () => ({ viewer: me, organization }),
  Teams: (v) => ({ teams: conn(teams, v.first, v.after) }),
  States: (v) => {
    const t = findTeam(v.id); if (!t) return NOT_FOUND('Team');
    return { team: { ...t, states: { nodes: states.filter((s) => s.team === t.id).map(({ team, ...s }) => s) } } };
  },
  Projects: (v) => {
    const t = findTeam(v.id); if (!t) return NOT_FOUND('Team');
    return { team: { projects: conn(projects.filter((p) => p.team === t.id).map(({ team, ...p }) => p), v.first, v.after) } };
  },
  Project: (v) => { const p = projects.find((x) => x.id === v.id); return p ? { project: { id: p.id, name: p.name } } : NOT_FOUND('Project'); },
  Labels: (v) => {
    const t = findTeam(v.id); if (!t) return NOT_FOUND('Team');
    return { team: { labels: conn(labels.filter((l) => l.team === t.id).map(({ team, ...l }) => l), v.first, v.after) } };
  },
  Members: (v) => {
    const t = findTeam(v.id); if (!t) return NOT_FOUND('Team');
    return { team: { members: conn(members[t.id] || [], v.first, v.after) } };
  },
  Issues: (v) => ({ issues: conn(live(issues).filter((w) => matches(w, v.filter)).map(issueOut), v.first, v.after) }),
  Issue: (v) => { const w = findIssue(v.id); return w ? { issue: issueOut(w) } : NOT_FOUND('Issue'); },
  Children: (v) => { const w = findIssue(v.id); return w ? { issue: { children: conn(kidsOf(w).map(kid), v.first, v.after) } } : NOT_FOUND('Issue'); },
  Sample: (v) => ({ issues: { nodes: live(issues).filter((w) => matches(w, v.filter)).slice(-20).map(issueOut) } }),
  IssueCreate: (v) => {
    const i = v.input || {};
    if (!findTeam(i.teamId)) return NOT_FOUND('Team');
    if (!i.title) return bad('title must not be empty');
    if (badState(i.teamId, i.stateId)) return bad('state is not in the team');
    if (i.parentId && !findIssue(i.parentId)) return NOT_FOUND('Issue');
    if (i.projectId && !projects.some((p) => p.id === i.projectId)) return NOT_FOUND('Project');
    const w = addIssue({ team: i.teamId });
    setFields(w, i);
    if (w.parent) w.parent = findIssue(w.parent).id;
    return { issueCreate: { success: true, issue: { id: w.id, identifier: keyOf(w) } } };
  },
  IssueUpdate: (v) => {
    const w = findIssue(v.id); if (!w) return NOT_FOUND('Issue');
    if (badState(w.team, v.input?.stateId)) return bad('state is not in the team');
    setFields(w, v.input || {});
    return { issueUpdate: { success: true } };
  },
  CommentCreate: (v) => {
    const w = findIssue(v.input?.issueId); if (!w) return NOT_FOUND('Issue');
    if (!v.input.body) return bad('body must not be empty');
    comments.push({ id: uuid(), issue: w.id, body: v.input.body });
    return { commentCreate: { success: true } };
  },
  // Keyed by issue and URL: the same URL again updates the attachment that is there.
  AttachmentCreate: (v) => {
    const i = v.input || {}, w = findIssue(i.issueId); if (!w) return NOT_FOUND('Issue');
    if (!i.url || !i.title) return bad('url and title are required');
    const old = attachments.find((a) => a.issue === w.id && a.url === i.url);
    if (old) old.title = i.title; else attachments.push({ id: uuid(), issue: w.id, url: i.url, title: i.title });
    return { attachmentCreate: { success: true } };
  },
  // Test-only: how many attachments an issue has, so a test can see that relinking did not add one.
  StubAttachments: (v) => ({ count: attachments.filter((a) => a.issue === findIssue(v.id)?.id).length }),
};

createServer((req, res) => {
  let raw = '';
  req.on('data', (c) => (raw += c));
  req.on('end', () => {
    let body = {};
    try { if (raw) body = JSON.parse(raw); } catch { body = {}; }
    const [, kind = '', op = ''] = String(body.query || '').match(/^\s*(query|mutation)\s+(\w+)/) || [];
    const vars = body.variables || {};
    const key = req.headers.authorization;
    if (op !== 'StubAttachments') appendFileSync(logFile, JSON.stringify({ op, kind, vars, creds: !!key }) + '\n');
    const send = (status, obj) => {
      res.statusCode = status;
      if (status === 429) res.setHeader('retry-after', '1');
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify(obj ?? { errors: [{ message: `error ${status}` }] }));
    };
    if (req.method !== 'POST') return send(405);
    const f = fails.find((x) => x.left > 0 && x.op === op);
    if (f) {
      f.left--;
      if (f.status !== 'RATELIMITED') return send(f.status);
      res.setHeader('retry-after', '1');
      return send(400, { errors: [{ message: 'Rate limit exceeded', extensions: { code: 'RATELIMITED' } }] });
    }
    if (!key) return send(401, { errors: [{ message: 'Authentication required, not authenticated', extensions: { code: 'AUTHENTICATION_ERROR' } }] });
    if (process.env.STUB_AUTH && process.env.STUB_AUTH !== key) return send(401, { errors: [{ message: 'Authentication required, not authenticated', extensions: { code: 'AUTHENTICATION_ERROR' } }] });
    if (!ops[op]) return send(400, bad(`unknown operation ${op || '(anonymous)'}`));
    const out = ops[op](vars);
    send(200, out.errors ? { data: null, errors: out.errors } : { data: out });
  });
}).listen(0, '127.0.0.1', function () { writeFileSync(portFile, String(this.address().port)); });
