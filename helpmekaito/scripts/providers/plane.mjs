// Plane: the project (or one module of it) is the truth, tasks/plane/<slug>/ is a read cache.
// B is "<projectId>" or "<projectId>/<moduleId>". A list is a state, a checklist item is a sub work item.
import { readFileSync, writeFileSync, mkdirSync, renameSync, rmSync, readdirSync, existsSync, utimesSync, copyFileSync, unlinkSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { plane, all, base, redact } from '../kaito-plane.mjs';
import { M, D, B, S, die, one, fm, slug, inside, taskFiles, writeIndex, locked, keepEdit, itemId, opts, httpUrl } from './lib.mjs';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const [PID = '', MID = ''] = String(B || '').split('/');
const WS = process.env.KAITO_PLANE_WORKSPACE || '';
const proj = (p = '') => `/projects/${PID}${p}`;
const mapFile = join(M, 'managers', 'plane.json');
const readMap = () => { try { return JSON.parse(readFileSync(mapFile, 'utf8')); } catch { return {}; } };
const CLOSED = ['completed', 'cancelled'];
const web = () => { const o = new URL(base()).origin; return o === 'https://api.plane.so' ? 'https://app.plane.so' : o; };

const liveStates = async (pid = PID) => (await all(`/projects/${pid}/states/`))
  .map((s) => ({ id: s.id, name: one(s.name), group: s.group, sequence: s.sequence ?? 0 })).sort((a, b) => a.sequence - b.sequence);
// States from the structure memory; a miss (renamed or new state) reads Plane once and updates the memory.
async function states(fresh = false) {
  const map = readMap(), b = map.boards?.[PID];
  if (!fresh && b?.states?.length) return b.states;
  const st = await liveStates();
  if (b) { b.states = st; try { writeFileSync(`${mapFile}.${process.pid}.tmp`, JSON.stringify(map, null, 2) + '\n'); renameSync(`${mapFile}.${process.pid}.tmp`, mapFile); } catch {} }
  return st;
}
async function findState(x) {
  const hit = (st) => st.find((s) => s.id === x) || st.find((s) => s.name.toLowerCase() === String(x).toLowerCase());
  return hit(await states()) || hit(await states(true)) || die(`no state ${x} in this project`);
}
const todoState = (st) => st.find((s) => s.group === 'unstarted') || st.find((s) => s.group === 'backlog') || st[0] || die('the project has no states');
const doneState = (st) => st.find((s) => s.group === 'completed');
async function ident() {
  const known = readMap().boards?.[PID]?.identifier;
  if (known) return known;
  const p = (await all('/projects/')).find((x) => x.id === PID) || die('this project is not in the workspace');
  return p.identifier;
}

const text = (html) => String(html || '').replace(/<\/(p|div|li|h[1-6])>|<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '')
  .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
  .replace(/\n{3,}/g, '\n\n').trim();
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const html = (s) => String(s).split(/\n+/).map((l) => l.trim()).filter(Boolean).map((l) => `<p>${esc(l)}</p>`).join('');
const ref = (v) => (typeof v === 'object' && v ? v.id : v) || '';
const sid = (w) => ref(w.state);
const pid = (w) => ref(w.parent);
const modId = (x) => ref(x.issue) || x.id;
const itemFile = (key, w) => `${key}-${slug(w.name)}.md`;
// kids: [{ id: "ALL-31", name, done }]
function itemText(w, key, st, kids, labels, at) {
  const s = st.find((x) => x.id === sid(w)) || { name: '', group: '' };
  const meta = { id: key, item_id: w.id, title: w.name, list: s.name, state_group: s.group, due: w.target_date ?? '', priority: w.priority ?? '',
    labels: (w.labels || []).map((l) => labels[typeof l === 'object' ? l.id : l] || '').filter(Boolean).join(', '),
    url: `${web()}/${WS}/browse/${key}/`, synced_at: at, generated: 'edit through helpmekaito' };
  let body = (w.description_stripped || text(w.description_html)).trim();
  if (kids.length) body += `\n\n### Sub-items\n${kids.map((k) => `- [${k.done ? 'x' : ' '}] ${one(k.name)} <!-- id:${k.id} -->`).join('\n')}`;
  return fm(meta) + body.trim() + '\n';
}
function writeItem(dir, w, key, st, kids, labels, at) {
  if (!/^[A-Za-z0-9]+-\d+$/.test(key)) throw new Error('plane sent an odd work item id');
  const f = inside(dir, itemFile(key, w));
  writeFileSync(f, itemText(w, key, st, kids, labels, at));
  const t = new Date(at); utimesSync(f, t, t);  // mtime = synced_at, so a later edit shows
}
const labelNames = () => Object.fromEntries((readMap().boards?.[PID]?.labels || []).map((l) => [l.id, l.name]));
const kidsOf = (body) => [...String(body).matchAll(/^- \[([ x])\] (.*) <!-- id:(\S+) -->$/gm)].map((m) => ({ id: m[3], name: m[2], done: m[1] === 'x' }));

async function pull() {
  const st = await liveStates(), key = await ident();
  // Scope: the mapped module's items, or the whole project. The docs give no parent filter, so children are grouped here.
  const mod = MID ? await all(proj(`/modules/${MID}/module-issues/`)) : null;
  const scope = mod ? new Set(mod.map(modId)) : null;
  let items;
  try { items = await all(proj('/work-items/')); } catch (e) {
    // Too big to read whole: never cache a partial list. A module that lists full work items can still be shown on its own.
    if (e.code !== 'TOO_MANY') throw e;
    if (!mod || !mod.every((x) => x.sequence_id && x.name)) die('this project has too many work items to read whole: map one of its modules (kaito-tasks.sh modules <projectId>)');
    console.error('warning: the project is too big to read whole; showing the module only, so sub-items outside the module are missing');
    items = mod;
  }
  const group = (w) => st.find((s) => s.id === sid(w))?.group || '';
  const byId = new Map(items.map((w) => [w.id, w]));
  const shown = (w) => !w.archived_at && !w.is_draft && !CLOSED.includes(group(w)) && (!scope || scope.has(w.id));
  // A sub-item sits under its parent only when the parent is itself listed; under a closed or out-of-scope parent it stands alone.
  const top = items.filter((w) => shown(w) && !(pid(w) && byId.has(pid(w)) && shown(byId.get(pid(w)))));
  const at = new Date().toISOString(), labels = labelNames();
  const tmp = join(dirname(D), `.${S}.new.${process.pid}`);
  try {
    mkdirSync(tmp, { recursive: true });
    for (const w of top) {
      const kids = items.filter((k) => pid(k) === w.id && !k.archived_at).sort((a, b) => a.sequence_id - b.sequence_id)
        .map((k) => ({ id: `${key}-${k.sequence_id}`, name: k.name, done: CLOSED.includes(group(k)) }));
      writeItem(tmp, w, `${key}-${w.sequence_id}`, st, kids, labels, at);
    }
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
  console.log(`pulled ${top.length} work items`);
}

// One GET for the item; its sub-items come from the cached file plus the change this op just made.
async function refresh(r, change) {
  const w = await plane('GET', proj(`/work-items/${r.id}/`));
  const st = await states(), key = `${await ident()}-${w.sequence_id}`;
  locked(() => {
    mkdirSync(D, { recursive: true });
    let kids = [];
    for (const t of taskFiles(D)) if (t.meta.item_id === w.id) { kids = kidsOf(t.body); keepEdit(t, join(D, 'conflicts')); unlinkSync(t.path); }
    if (change) kids = change(kids);
    const closed = CLOSED.includes(st.find((s) => s.id === sid(w))?.group);
    if (!closed && !w.archived_at) writeItem(D, w, key, st, kids, labelNames(), new Date().toISOString());
    writeIndex();
  });
}

// A task is named by its key (ALL-27), a prefix of it, or its UUID.
async function resolve(arg) {
  if (!arg || !/^[A-Za-z0-9-]+$/.test(arg)) die(`bad task id ${arg ?? ''}`);
  const ts = taskFiles(D), up = arg.toUpperCase();
  const exact = ts.find((t) => String(t.meta.id).toUpperCase() === up || t.meta.item_id === arg);
  if (exact) return { id: exact.meta.item_id, short: exact.meta.id, cached: true };
  if (UUID.test(arg)) return { id: arg, short: arg };
  if (/^[A-Za-z0-9]+-\d+$/.test(arg)) {
    const w = await plane('GET', `/work-items/${up}/`);
    if (ref(w.project) && ref(w.project) !== PID) die(`${up} is in another project, not the one this repo is mapped to`);
    return { id: w.id, short: up, item: w };
  }
  die(`no task ${arg}: use its key (like ALL-27) or run pull`);
}

// A repo mapped to one module only writes to that module's items and their sub-items. Cached items came from a scoped pull.
async function inModule(r) {
  if (!MID || r.cached) return;
  const w = r.item || await plane('GET', proj(`/work-items/${r.id}/`));
  const ids = new Set((await all(proj(`/modules/${MID}/module-issues/`))).map(modId));
  if (!ids.has(w.id) && !ids.has(pid(w))) die(`${r.short} is not in the module this repo is mapped to: add it to the module in Plane, or map the whole project`);
}
// The item exists by now, so a failed module step must not read as a failed create: a retry would make a second item.
async function toModule(id, short) {
  if (!MID) return;
  try { await plane('POST', proj(`/modules/${MID}/module-issues/`), { issues: [id] }); }
  catch (e) { console.error(`warning: ${short} was created but not added to the module (${redact(e.message)}). Add it to the module in Plane; do not create it again.`); }
}

// New items go to the person whose key this is. Known from the structure memory, else asked once; a non-member or a failed lookup leaves the item unassigned.
async function mine() {
  const map = readMap(), members = map.boards?.[PID]?.members;
  let id = map.me?.id;
  if (!id) try { id = (await plane('GET', '/users/me/')).id; } catch { return []; }
  return id && (!members?.length || members.some((m) => m.id === id)) ? [id] : [];
}

async function op(op, a) {
  let r, title, change;
  const st = async () => states();
  if (op === 'add') {
    title = one(a[0]); if (!title) die('add needs a title');
    const o = opts(a.slice(1));
    const body = { name: title, state: (o.list ? await findState(o.list) : todoState(await st())).id };
    if (o.due) body.target_date = new Date(o.due).toISOString().slice(0, 10);
    if (o.desc) body.description_html = html(o.desc);
    const me = await mine(); if (me.length) body.assignees = me;
    const w = await plane('POST', proj('/work-items/'), body);
    r = { id: w.id, short: `${await ident()}-${w.sequence_id}` };
    await toModule(w.id, r.short);
  } else {
    r = await resolve(a[0]);
    await inModule(r);
    const path = proj(`/work-items/${r.id}/`);
    if (op === 'item-add') {
      const t = one(a[1]); if (!t) die('item add needs text');
      const me = await mine();
      const k = await plane('POST', proj('/work-items/'), { name: t, parent: r.id, state: todoState(await st()).id, ...(me.length ? { assignees: me } : {}) });
      const kid = { id: `${await ident()}-${k.sequence_id}`, name: t, done: false };
      await toModule(k.id, kid.id);
      change = (kids) => [...kids, kid];
    } else if (op === 'check' || op === 'uncheck') {
      const kid = await resolve(itemId(a[1])), all = await st();
      const kw = kid.item || await plane('GET', proj(`/work-items/${kid.id}/`));
      if (pid(kw) !== r.id) die(`${kid.short} is not a sub-item of ${r.short}`);
      const to = op === 'check' ? doneState(all) || die('the project has no completed state') : todoState(all);
      await plane('PATCH', proj(`/work-items/${kid.id}/`), { state: to.id });
      change = (kids) => kids.map((k) => (k.id.toUpperCase() === kid.short.toUpperCase() ? { ...k, done: op === 'check' } : k));
    } else if (op === 'rename') {
      const t = one(a[1]); if (!t) die('rename needs a title');
      await plane('PATCH', path, { name: t });
    } else if (op === 'move') {
      if (!a[1]) die('move needs a state');
      await plane('PATCH', path, { state: (await findState(a[1])).id });
    } else if (op === 'comment') {
      if (!a[1]) die('comment needs text');
      await plane('POST', `${path}comments/`, { comment_html: html(a[1]) });
    } else if (op === 'link') {
      const body = { url: httpUrl(a[1]) };
      if (one(a[2])) body.title = one(a[2]);
      await plane('POST', `${path}links/`, body);
    } else if (op === 'done') {
      await plane('PATCH', path, { state: (doneState(await st()) || die('the project has no completed state')).id });
    } else if (op === 'reopen') {
      await plane('PATCH', path, { state: todoState(await st()).id });
    } else die(`unknown command ${op}`);
  }
  try { await refresh(r, change); } catch { console.log(`remote ok (${r.short}), local refresh failed: run pull`); return; }
  console.log(op === 'add' ? `added ${r.short} ${title}` : `ok ${r.short}`);
}

// ---- structure memory: projects, states, labels, members, modules and a derived item style; never item names or descriptions ----
function style(items) {
  const n = items.length, pct = (k) => `${n ? Math.round((100 * k) / n) : 0}%`, cnt = (f) => items.filter(f).length;
  let title = 'free text';
  for (const [name, re] of [['bracket prefix', /^\[[^\]]+\]\s/], ['colon prefix', /^[^:\s][^:]{0,24}:\s/]]) {
    const k = cnt((w) => re.test(w.name || ''));
    if (k > 0 && k * 2 >= n) { title = `${name} ${pct(k)}`; break; }
  }
  return { sampled: n, title_pattern: title, description_rate: pct(cnt((w) => (w.description_stripped || text(w.description_html)).length > 0)),
    due_rate: pct(cnt((w) => w.target_date)), label_rate: pct(cnt((w) => (w.labels || []).length > 0)),
    sub_item_rate: pct(cnt((w) => w.parent)), priority_rate: pct(cnt((w) => w.priority && w.priority !== 'none')) };
}
function render(map) {
  const md = ['<!-- generated from plane.json by kaito-tasks.sh discover; do not edit -->', '# Plane project map', '',
    `Discovered ${map.generated_at}. Item style comes from the last 20 work items. No work item names or descriptions are stored.`,
    `Workspace: ${map.workspace || ''}`, `Me: ${map.me?.display_name || ''} (${map.me?.id || ''})`];
  for (const [id, b] of Object.entries(map.boards || {})) {
    const s = b.item_style, j = (xs) => (xs || []).join(', ') || 'none';
    md.push('', `## ${b.name} [${b.identifier}] (${id})`, '',
      `- States: ${j((b.states || []).map((x) => `${x.name} ${x.group} (${x.id})`))}`,
      `- Modules: ${j((b.modules || []).map((x) => `${x.name} (${x.id})`))}`,
      `- Labels: ${j((b.labels || []).map((x) => `${x.name} (${x.id})`))}`,
      `- Members: ${j((b.members || []).map((x) => `${x.display_name} (${x.id})`))}`);
    if (s) md.push(`- Item style (${s.sampled} items): titles ${s.title_pattern}; description ${s.description_rate}; due ${s.due_rate}; labels ${s.label_rate}; sub-items ${s.sub_item_rate}; priority ${s.priority_rate}`);
  }
  return md.join('\n') + '\n';
}
function save(map) {
  const dir = join(M, 'managers'), mdFile = join(dir, 'plane.md');
  mkdirSync(dir, { recursive: true });
  writeFileSync(`${mapFile}.${process.pid}.tmp`, JSON.stringify(map, null, 2) + '\n');
  writeFileSync(`${mdFile}.${process.pid}.tmp`, render(map));
  renameSync(`${mapFile}.${process.pid}.tmp`, mapFile);
  renameSync(`${mdFile}.${process.pid}.tmp`, mdFile);
}
async function discover(ids) {
  const me = await plane('GET', '/users/me/');
  const projects = await all('/projects/'), boards = {};
  for (const id of ids) {
    if (!UUID.test(id)) die(`bad project id ${id}`);
    const p = projects.find((x) => x.id === id) || die(`no project ${id} in workspace ${WS}`);
    const get = (path) => all(`/projects/${id}${path}`);
    const items = (await plane('GET', `/projects/${id}/work-items/?per_page=20&order_by=-created_at`)).results || [];
    boards[id] = { name: one(p.name), identifier: p.identifier, states: await liveStates(id),
      modules: (await get('/modules/')).map((m) => ({ id: m.id, name: one(m.name) })),
      labels: (await get('/labels/')).map((l) => ({ id: l.id, name: one(l.name), color: l.color ?? '' })),
      members: (await get('/project-members/')).map((m) => ({ id: m.id, display_name: one(m.display_name) })),
      item_style: style(items) };
  }
  save({ generated_at: new Date().toISOString(), workspace: WS, me: { id: me.id, display_name: one(me.display_name) }, boards });
  console.log(`discovered ${ids.length} project(s): ${mapFile}`);
}
// MCP path: the agent read the structure with the Plane MCP and hands it over as JSON on stdin, same shape as discover writes.
function structurePut() {
  let map;
  try { map = JSON.parse(readFileSync(0, 'utf8')); } catch { die('structure put needs the structure as JSON on stdin'); }
  if (!map || typeof map.boards !== 'object' || !Object.keys(map.boards).every((id) => UUID.test(id))) die('structure put: boards must be keyed by project id');
  if (/((api[_ -]?key|token|passw(or)?d|secret)"?\s*[:=]|bearer\s+[a-z0-9._-]{12,}|plane_api_)/i.test(JSON.stringify(map))) die('refusing to store what looks like a secret');
  save({ ...map, generated_at: new Date().toISOString() });
  console.log(`stored structure for ${Object.keys(map.boards).length} project(s): ${mapFile}`);
}
const name = (xs, id, what) => xs.find((x) => x.id === id)?.name || die(`no ${what} ${id}`);

export default {
  remote: true,
  indexDone: true,
  isDone: (t) => CLOSED.includes(t.meta.state_group),
  where: (t) => t.meta.list,
  redact,
  commands: {
    boards: async () => { for (const p of await all('/projects/')) if (!p.archived_at) console.log(`${p.id} ${p.identifier} ${one(p.name)}`); },
    modules: async ([id]) => { for (const m of await all(`/projects/${id}/modules/`)) if (!m.archived_at) console.log(`${id}/${m.id} ${one(m.name)}`); },
    'board-name': async ([id]) => {
      const [p, m] = id.split('/');
      const pn = one(name(await all('/projects/'), p, 'project'));
      console.log(m ? `${pn} / ${one(name(await all(`/projects/${p}/modules/`), m, 'module'))}` : pn);
    },
    me: async () => console.log(one((await plane('GET', '/users/me/')).display_name)),
    discover,
    'structure-put': structurePut,
    pull,
  },
  op,
};
