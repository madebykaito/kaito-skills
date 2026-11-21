// Linear: the team (or one project of it) is the truth, tasks/linear/<slug>/ is a read cache.
// B is "<teamId>" or "<teamId>/<projectId>". A list is a workflow state, a checklist item is a sub-issue.
import { readFileSync, writeFileSync, writeSync, mkdirSync, renameSync, rmSync, readdirSync, existsSync, utimesSync, copyFileSync, unlinkSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { linear, all, redact } from '../kaito-linear.mjs';
import { M, D, B, S, die, one, fm, slug, inside, taskFiles, writeIndex, locked, keepEdit, itemId, opts, httpUrl } from './lib.mjs';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const KEY = /^[A-Za-z][A-Za-z0-9]*-\d+$/;
const [TID = '', PJ = ''] = String(B || '').split('/');
const mapFile = join(M, 'managers', 'linear.json');
const readMap = () => { try { return JSON.parse(readFileSync(mapFile, 'utf8')); } catch { return {}; } };
const CLOSED = ['completed', 'canceled', 'duplicate'];
const ORDER = ['triage', 'backlog', 'unstarted', 'started', 'completed', 'canceled', 'duplicate'];
const PRIORITY = ['', 'urgent', 'high', 'medium', 'low'];

const PAGEINFO = 'pageInfo { hasNextPage endCursor }';
const KID = 'id identifier title archivedAt state { type }';
const ISSUE = `id identifier title description dueDate priority url archivedAt state { id name type } labels(first: 10) { nodes { name } }
  team { id } project { id } parent { id identifier project { id } }`;
const Q = {
  viewer: 'query Viewer { viewer { id name displayName } organization { name urlKey } }',
  teams: `query Teams($first: Int, $after: String) { teams(first: $first, after: $after) { nodes { id key name } ${PAGEINFO} } }`,
  states: 'query States($id: String!) { team(id: $id) { id key name states(first: 100) { nodes { id name type position } } } }',
  projects: `query Projects($id: String!, $first: Int, $after: String) { team(id: $id) { projects(first: $first, after: $after) { nodes { id name status { type } } ${PAGEINFO} } } }`,
  project: 'query Project($id: String!) { project(id: $id) { id name } }',
  labels: `query Labels($id: String!, $first: Int, $after: String) { team(id: $id) { labels(first: $first, after: $after) { nodes { id name color } ${PAGEINFO} } } }`,
  members: `query Members($id: String!, $first: Int, $after: String) { team(id: $id) { members(first: $first, after: $after) { nodes { id displayName } ${PAGEINFO} } } }`,
  issues: `query Issues($filter: IssueFilter, $first: Int, $after: String) { issues(first: $first, after: $after, filter: $filter) {
    nodes { ${ISSUE} children(first: 25) { nodes { ${KID} } pageInfo { hasNextPage } } } ${PAGEINFO} } }`,
  issue: `query Issue($id: String!) { issue(id: $id) { ${ISSUE} children(first: 50) { nodes { ${KID} } pageInfo { hasNextPage } } } }`,
  children: `query Children($id: String!, $first: Int, $after: String) { issue(id: $id) { children(first: $first, after: $after) { nodes { ${KID} } ${PAGEINFO} } } }`,
  sample: 'query Sample($filter: IssueFilter) { issues(first: 20, filter: $filter) { nodes { title description dueDate priority labels(first: 1) { nodes { id } } parent { id } } } }',
  create: 'mutation IssueCreate($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { id identifier } } }',
  update: 'mutation IssueUpdate($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) { success } }',
  comment: 'mutation CommentCreate($input: CommentCreateInput!) { commentCreate(input: $input) { success } }',
  attach: 'mutation AttachmentCreate($input: AttachmentCreateInput!) { attachmentCreate(input: $input) { success } }',
};

const sortStates = (xs) => xs.map((s) => ({ id: s.id, name: one(s.name), group: s.type, sequence: s.position ?? 0 }))
  .sort((a, b) => ORDER.indexOf(a.group) - ORDER.indexOf(b.group) || a.sequence - b.sequence);
// Linear answers an unknown id with an error, not a null: "Entity not found", code INPUT_ERROR.
const found = (p) => p.catch((e) => { if (e.code === 'INPUT_ERROR' && /not found/i.test(e.message)) return {}; throw e; });
// Throws, never dies: a pull's structure refresh must be able to step over a team the key can no longer read.
async function team(id = TID) {
  if (!UUID.test(id)) throw new Error(`bad team id ${id}`);
  const t = (await found(linear(Q.states, { id }))).team;
  if (!t) throw new Error(`no team ${id} in this workspace`);
  return t;
}
const liveStates = async (id = TID) => sortStates((await team(id)).states?.nodes || []);
// States from the structure memory; a miss (renamed or new state) reads Linear once and updates the memory.
async function states(fresh = false) {
  const map = readMap(), b = map.boards?.[TID];
  if (!fresh && b?.states?.length) return b.states;
  const st = await liveStates();
  if (b) { b.states = st; try { writeFileSync(`${mapFile}.${process.pid}.tmp`, JSON.stringify(map, null, 2) + '\n'); renameSync(`${mapFile}.${process.pid}.tmp`, mapFile); } catch {} }
  return st;
}
async function findState(x) {
  const hit = (st) => st.find((s) => s.id === x) || st.find((s) => s.name.toLowerCase() === String(x).toLowerCase());
  return hit(await states()) || hit(await states(true)) || die(`no state ${x} in this team`);
}
const todoState = (st) => st.find((s) => s.group === 'unstarted') || st.find((s) => s.group === 'backlog') || st[0] || die('the team has no states');
const doneState = (st) => st.find((s) => s.group === 'completed');

const num = (key) => Number(String(key).split('-').pop());
const kidRows = (nodes) => nodes.filter((k) => !k.archivedAt).sort((a, b) => num(a.identifier) - num(b.identifier))
  .map((k) => ({ id: k.identifier, name: k.title, done: CLOSED.includes(k.state?.type) }));
// The issue query carries the first sub-issues; an issue with more reads the rest page by page.
async function kidsOf(w) {
  if (!w.children?.pageInfo?.hasNextPage) return kidRows(w.children?.nodes || []);
  return kidRows(await all(Q.children, { id: w.id }, (d) => d.issue?.children));
}
const itemFile = (w) => `${w.identifier}-${slug(w.title)}.md`;
// kids: [{ id: "KAI-31", name, done }]
function itemText(w, kids, at) {
  const meta = { id: w.identifier, item_id: w.id, title: w.title, list: one(w.state?.name), state_group: w.state?.type ?? '', due: w.dueDate ?? '',
    priority: PRIORITY[w.priority] ?? '', labels: (w.labels?.nodes || []).map((l) => one(l.name)).filter(Boolean).join(', '),
    url: w.url ?? '', synced_at: at, generated: 'edit through helpmekaito' };
  let body = String(w.description || '').trim();
  if (kids.length) body += `\n\n### Sub-items\n${kids.map((k) => `- [${k.done ? 'x' : ' '}] ${one(k.name)} <!-- id:${k.id} -->`).join('\n')}`;
  return fm(meta) + body.trim() + '\n';
}
function writeItem(dir, w, kids, at) {
  if (!KEY.test(w.identifier || '')) throw new Error('linear sent an odd issue id');
  const f = inside(dir, itemFile(w));
  writeFileSync(f, itemText(w, kids, at));
  const t = new Date(at); utimesSync(f, t, t);  // mtime = synced_at, so a later edit shows
}

async function pull() {
  // Only open issues are read: the team's, or the mapped project's. Closed sub-issues still come along under their parent.
  const filter = { team: { id: { eq: TID } }, state: { type: { nin: CLOSED } } };
  if (PJ) filter.project = { id: { eq: PJ } };
  let items;
  try { items = await all(Q.issues, { filter }, (d) => d.issues); } catch (e) {
    if (e.code !== 'TOO_MANY') throw e;
    die(`this ${PJ ? 'project' : 'team'} has too many open issues to read whole${PJ ? '' : ': map one of its projects (kaito-tasks.sh projects <teamId>)'}`);
  }
  items = items.filter((w) => !w.archivedAt);
  // A sub-issue sits under its parent only when the parent has a file of its own; under a closed, out-of-scope
  // or nested parent (a sub-issue's sub-issue) it stands alone, so every open issue is in some file.
  const byId = new Map(items.map((w) => [w.id, w])), isTop = new Map();
  const topOf = (w, seen = new Set()) => {
    if (!isTop.has(w.id)) {
      const p = w.parent && byId.get(w.parent.id);
      seen.add(w.id);
      isTop.set(w.id, !p || seen.has(p.id) || !topOf(p, seen));
    }
    return isTop.get(w.id);
  };
  const top = items.filter((w) => topOf(w));
  const at = new Date().toISOString();
  const tmp = join(dirname(D), `.${S}.new.${process.pid}`);
  try {
    mkdirSync(tmp, { recursive: true });
    for (const w of top) writeItem(tmp, w, await kidsOf(w), at);
    writeIndex(tmp);
  } catch (e) { rmSync(tmp, { recursive: true, force: true }); throw e; }
  locked(() => {
    if (existsSync(D)) {
      const cdir = join(tmp, 'conflicts');
      for (const t of taskFiles(D)) keepEdit(t, cdir);
      const old = join(D, 'conflicts');
      if (existsSync(old)) for (const f of readdirSync(old)) {
        mkdirSync(cdir, { recursive: true });
        if (!existsSync(join(cdir, f))) copyFileSync(join(old, f), join(cdir, f));
      }
      const gone = `${tmp}.old`;
      renameSync(D, gone); renameSync(tmp, D); rmSync(gone, { recursive: true, force: true });
    } else renameSync(tmp, D);
  });
  console.log(`pulled ${top.length} issues`);
}

const fetchIssue = async (id) => (await found(linear(Q.issue, { id }))).issue || die(`no issue ${id}`);
// One query for the issue and its sub-issues, then the cached file is rewritten (or dropped once the issue is closed).
async function refresh(r) {
  const w = await fetchIssue(r.id), kids = await kidsOf(w);
  locked(() => {
    mkdirSync(D, { recursive: true });
    for (const t of taskFiles(D)) if (t.meta.item_id === w.id) { keepEdit(t, join(D, 'conflicts')); unlinkSync(t.path); }
    if (!CLOSED.includes(w.state?.type) && !w.archivedAt) writeItem(D, w, kids, new Date().toISOString());
    writeIndex();
  });
}

// A task is named by its identifier (KAI-27) or its UUID.
async function resolve(arg) {
  if (!arg || !/^[A-Za-z0-9-]+$/.test(arg)) die(`bad task id ${arg ?? ''}`);
  const ts = taskFiles(D), up = arg.toUpperCase();
  const exact = ts.find((t) => String(t.meta.id).toUpperCase() === up || t.meta.item_id === arg);
  if (exact) return { id: exact.meta.item_id, short: exact.meta.id, cached: true };
  if (!UUID.test(arg) && !KEY.test(arg)) die(`no task ${arg}: use its id (like KAI-27) or run pull`);
  const w = await fetchIssue(UUID.test(arg) ? arg : up);
  if (w.team?.id !== TID) die(`${w.identifier} is in another team, not the one this repo is mapped to`);
  return { id: w.id, short: w.identifier, item: w };
}
// A repo mapped to one project only writes to that project's issues and their sub-issues. Cached issues came from a scoped pull.
async function inProject(r) {
  if (!PJ || r.cached) return;
  const w = r.item || await fetchIssue(r.id);
  if (w.project?.id !== PJ && w.parent?.project?.id !== PJ) die(`${r.short} is not in the project this repo is mapped to: add it to the project in Linear, or map the whole team`);
}
// New issues go to the person whose key this is. Known from the structure memory, else asked once; a failed lookup leaves the issue unassigned.
async function mine() {
  const id = readMap().me?.id;
  if (id) return id;
  try { return (await linear(Q.viewer)).viewer.id; } catch { return ''; }
}
async function create(input) {
  const me = await mine();
  if (me) input.assigneeId = me;
  if (PJ) input.projectId = PJ;
  const r = (await linear(Q.create, { input: { teamId: TID, ...input } })).issueCreate;
  if (!r?.success || !r.issue) throw new Error('linear did not create the issue');
  return r.issue;
}
const update = async (id, input) => {
  if (!(await linear(Q.update, { id, input })).issueUpdate?.success) throw new Error('linear did not save the change');
};

async function op(op, a) {
  let r, title;
  if (!UUID.test(TID)) die(`bad team id ${TID}`);
  if (op === 'add') {
    title = one(a[0]); if (!title) die('add needs a title');
    const o = opts(a.slice(1));
    const input = { title, stateId: (o.list ? await findState(o.list) : todoState(await states())).id };
    if (o.due) input.dueDate = new Date(o.due).toISOString().slice(0, 10);
    if (o.desc) input.description = String(o.desc);
    const w = await create(input);
    r = { id: w.id, short: w.identifier };
  } else {
    r = await resolve(a[0]);
    await inProject(r);
    if (op === 'item-add') {
      const t = one(a[1]); if (!t) die('item add needs text');
      await create({ title: t, parentId: r.id, stateId: todoState(await states()).id });
    } else if (op === 'check' || op === 'uncheck') {
      const kid = await resolve(itemId(a[1])), st = await states();
      const kw = kid.item || await fetchIssue(kid.id);
      if (kw.parent?.id !== r.id) die(`${kid.short} is not a sub-item of ${r.short}`);
      const to = op === 'check' ? doneState(st) || die('the team has no completed state') : todoState(st);
      await update(kid.id, { stateId: to.id });
    } else if (op === 'rename') {
      const t = one(a[1]); if (!t) die('rename needs a title');
      await update(r.id, { title: t });
    } else if (op === 'move') {
      if (!a[1]) die('move needs a state');
      await update(r.id, { stateId: (await findState(a[1])).id });
    } else if (op === 'comment') {
      if (!a[1]) die('comment needs text');
      if (!(await linear(Q.comment, { input: { issueId: r.id, body: String(a[1]) } })).commentCreate?.success) throw new Error('linear did not save the comment');
    } else if (op === 'link') {
      // Linear keys an attachment by issue and URL: linking the same URL again updates the one that is there.
      const url = httpUrl(a[1]);
      if (!(await linear(Q.attach, { input: { issueId: r.id, url, title: one(a[2]) || url } })).attachmentCreate?.success) throw new Error('linear did not save the link');
    } else if (op === 'done') {
      await update(r.id, { stateId: (doneState(await states()) || die('the team has no completed state')).id });
    } else if (op === 'reopen') {
      await update(r.id, { stateId: todoState(await states()).id });
    } else die(`unknown command ${op}`);
  }
  // The remote write is done: from here any failure, a die() in the lock or the fetch included, still reports it,
  // so nobody retries a write that already happened.
  const said = `remote ok (${r.short}), local refresh failed: run pull\n`;
  const guard = (code) => { if (code) { writeSync(1, said); process.exitCode = 0; } };
  process.on('exit', guard);
  try { await refresh(r); } catch { process.off('exit', guard); writeSync(1, said); return; }
  process.off('exit', guard);
  console.log(op === 'add' ? `added ${r.short} ${title}` : `ok ${r.short}`);
}

// ---- structure memory: teams, states, projects, labels, members and a derived issue style; never issue titles or descriptions ----
function style(items) {
  const n = items.length, pct = (k) => `${n ? Math.round((100 * k) / n) : 0}%`, cnt = (f) => items.filter(f).length;
  let title = 'free text';
  for (const [name, re] of [['bracket prefix', /^\[[^\]]+\]\s/], ['colon prefix', /^[^:\s][^:]{0,24}:\s/]]) {
    const k = cnt((w) => re.test(w.title || ''));
    if (k > 0 && k * 2 >= n) { title = `${name} ${pct(k)}`; break; }
  }
  return { sampled: n, title_pattern: title, description_rate: pct(cnt((w) => String(w.description || '').trim().length > 0)),
    due_rate: pct(cnt((w) => w.dueDate)), label_rate: pct(cnt((w) => (w.labels?.nodes || []).length > 0)),
    sub_item_rate: pct(cnt((w) => w.parent)), priority_rate: pct(cnt((w) => w.priority > 0)) };
}
function render(map) {
  const md = ['<!-- generated from linear.json by kaito-tasks.sh discover; do not edit -->', '# Linear team map', '',
    `Discovered ${map.generated_at}. Issue style comes from the last 20 issues. No issue titles or descriptions are stored.`,
    `Workspace: ${map.workspace || ''}`, `Me: ${map.me?.display_name || ''} (${map.me?.id || ''})`];
  for (const [id, b] of Object.entries(map.boards || {})) {
    const s = b.item_style, j = (xs) => (xs || []).join(', ') || 'none';
    md.push('', `## ${b.name} [${b.identifier}] (${id})`, '',
      `- States: ${j((b.states || []).map((x) => `${x.name} ${x.group} (${x.id})`))}`,
      `- Projects: ${j((b.modules || []).map((x) => `${x.name} (${x.id})`))}`,
      `- Labels: ${j((b.labels || []).map((x) => `${x.name} (${x.id})`))}`,
      `- Members: ${j((b.members || []).map((x) => `${x.display_name} (${x.id})`))}`);
    if (s) md.push(`- Issue style (${s.sampled} issues): titles ${s.title_pattern}; description ${s.description_rate}; due ${s.due_rate}; labels ${s.label_rate}; sub-issues ${s.sub_item_rate}; priority ${s.priority_rate}`);
  }
  return md.join('\n') + '\n';
}
function save(map) {
  const dir = join(M, 'managers'), mdFile = join(dir, 'linear.md');
  mkdirSync(dir, { recursive: true });
  writeFileSync(`${mapFile}.${process.pid}.tmp`, JSON.stringify(map, null, 2) + '\n');
  writeFileSync(`${mdFile}.${process.pid}.tmp`, render(map));
  renameSync(`${mapFile}.${process.pid}.tmp`, mapFile);
  renameSync(`${mdFile}.${process.pid}.tmp`, mdFile);
}
const openProjects = async (id) => (await all(Q.projects, { id }, (d) => d.team?.projects))
  .filter((p) => !CLOSED.includes(p.status?.type)).map((p) => ({ id: p.id, name: one(p.name) }));
// A team's projects are called modules in the stored map, so every manager's map has one shape.
async function discover(ids) {
  const who = await linear(Q.viewer), boards = {};
  for (const id of ids) {
    const t = await team(id);
    const sample = (await linear(Q.sample, { filter: { team: { id: { eq: id } } } })).issues?.nodes || [];
    boards[id] = { name: one(t.name), identifier: t.key, states: sortStates(t.states?.nodes || []),
      modules: await openProjects(id),
      labels: (await all(Q.labels, { id }, (d) => d.team?.labels)).map((l) => ({ id: l.id, name: one(l.name), color: l.color ?? '' })),
      members: (await all(Q.members, { id }, (d) => d.team?.members)).map((m) => ({ id: m.id, display_name: one(m.displayName) })),
      item_style: style(sample) };
  }
  save({ generated_at: new Date().toISOString(), workspace: one(who.organization?.urlKey || who.organization?.name),
    me: { id: who.viewer.id, display_name: one(who.viewer.displayName || who.viewer.name) }, boards });
  console.log(`discovered ${ids.length} team(s): ${mapFile}`);
}
// MCP path: the agent read the structure with the Linear MCP and hands it over as JSON on stdin, same shape as discover writes.
function structurePut() {
  let map;
  try { map = JSON.parse(readFileSync(0, 'utf8')); } catch { die('structure put needs the structure as JSON on stdin'); }
  if (!map || typeof map.boards !== 'object' || !Object.keys(map.boards).every((id) => UUID.test(id))) die('structure put: boards must be keyed by team id');
  if (/((api[_ -]?key|token|passw(or)?d|secret)"?\s*[:=]|bearer\s+[a-z0-9._-]{12,}|lin_(api|oauth)_)/i.test(JSON.stringify(map))) die('refusing to store what looks like a secret');
  save({ ...map, generated_at: new Date().toISOString() });
  console.log(`stored structure for ${Object.keys(map.boards).length} team(s): ${mapFile}`);
}

export default {
  remote: true,
  indexDone: true,
  isDone: (t) => CLOSED.includes(t.meta.state_group),
  where: (t) => t.meta.list,
  redact,
  commands: {
    boards: async () => { for (const t of await all(Q.teams, {}, (d) => d.teams)) console.log(`${t.id} ${t.key} ${one(t.name)}`); },
    projects: async ([id]) => { await team(id); for (const p of await openProjects(id)) console.log(`${id}/${p.id} ${p.name}`); },
    'board-name': async ([id]) => {
      const [t, p] = id.split('/');
      const tn = one((await team(t)).name);
      if (!p) return console.log(tn);
      if (!UUID.test(p)) die(`bad project id ${p}`);
      if (!(await openProjects(t)).some((x) => x.id === p)) die(`no project ${p} in team ${tn}`);
      console.log(`${tn} / ${one((await linear(Q.project, { id: p })).project?.name)}`);
    },
    me: async () => { const v = (await linear(Q.viewer)).viewer; console.log(one(v.displayName || v.name)); },
    discover,
    'structure-put': structurePut,
    pull,
  },
  op,
};
