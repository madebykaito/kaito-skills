// Trello: the board is the truth, tasks/trello/<slug>/ is a read cache.
import { readFileSync, writeFileSync, mkdirSync, renameSync, rmSync, readdirSync, existsSync, utimesSync, copyFileSync, unlinkSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { trello, redact } from '../kaito-trello.mjs';
import { M, D, B, S, die, one, fm, slug, inside, taskFiles, writeIndex, locked, keepEdit, itemId, opts, httpUrl } from './lib.mjs';

const mapFile = join(M, 'managers', 'trello.json');
const readMap = () => { try { return JSON.parse(readFileSync(mapFile, 'utf8')); } catch { return {}; } };
async function boardLists() {
  const b = readMap().boards?.[B];
  if (b?.lists?.length) return b.lists;
  return (await trello('GET', `/boards/${B}/lists?filter=open&fields=name,pos`)).map(({ id, name }) => ({ id, name }));
}
const findList = (lists, x) => lists.find((l) => l.id === x) || lists.find((l) => l.name.toLowerCase() === String(x).toLowerCase()) || die(`no list ${x} on this board`);
const todoList = (lists) => lists.find((l) => /^(to ?do|backlog)$/i.test(l.name)) || lists[0] || die('the board has no lists');
const doneList = (lists) => lists.find((l) => /^done$/i.test(l.name));
const CARD = 'fields=name,desc,due,idList,idBoard,labels,shortLink,url,closed&checklists=all';
const cardFile = (c) => `${c.shortLink}-${slug(c.name)}.md`;
function cardText(c, names, at) {
  if (!/^[A-Za-z0-9]+$/.test(c.shortLink || '')) throw new Error('trello sent an odd card id');
  const meta = { id: c.shortLink, card_id: c.id, title: c.name, list: names[c.idList] ?? '', list_id: c.idList, due: c.due ?? '',
    labels: (c.labels || []).map((l) => l.name || l.color).join(', '), url: c.url ?? '', synced_at: at, generated: 'edit through helpmekaito' };
  let body = String(c.desc || '').trim();
  for (const cl of c.checklists || []) {
    const its = [...(cl.checkItems || [])].sort((a, b) => a.pos - b.pos)
      .map((i) => `- [${i.state === 'complete' ? 'x' : ' '}] ${one(i.name)} <!-- id:${i.id} -->`);
    body += `\n\n### ${one(cl.name)} <!-- id:${cl.id} -->\n${its.join('\n')}`;
  }
  return fm(meta) + body.trim() + '\n';
}
function writeCard(dir, c, names, at) {
  const f = inside(dir, cardFile(c));
  writeFileSync(f, cardText(c, names, at));
  const t = new Date(at); utimesSync(f, t, t);  // mtime = synced_at, so a later edit shows
}
const namesOf = (lists) => Object.fromEntries(lists.map((l) => [l.id, l.name]));

async function pull() {
  const lists = await trello('GET', `/boards/${B}/lists?filter=open&fields=name,pos`);
  const cards = await trello('GET', `/boards/${B}/cards/open?${CARD}`);
  const at = new Date().toISOString(), names = namesOf(lists);
  const tmp = join(dirname(D), `.${S}.new.${process.pid}`);
  try {
    mkdirSync(tmp, { recursive: true });
    for (const c of cards) writeCard(tmp, c, names, at);
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
  console.log(`pulled ${cards.length} cards`);
}

async function refresh(id) {
  const c = await trello('GET', `/cards/${id}?${CARD}`);
  const lists = await boardLists();
  locked(() => {
    mkdirSync(D, { recursive: true });
    for (const t of taskFiles(D)) if (t.meta.card_id === c.id) { keepEdit(t, join(D, 'conflicts')); unlinkSync(t.path); }
    if (!c.closed && c.idBoard === B) writeCard(D, c, namesOf(lists), new Date().toISOString());
    writeIndex();
  });
}

function resolveCard(arg) {
  if (!arg || !/^[A-Za-z0-9]+$/.test(arg)) die(`bad task id ${arg ?? ''}`);
  const ts = taskFiles(D);
  const exact = ts.find((t) => t.meta.id === arg || t.meta.card_id === arg);
  if (exact) return { id: exact.meta.card_id, short: exact.meta.id };
  const hits = ts.filter((t) => String(t.meta.id).startsWith(arg) || String(t.meta.card_id).startsWith(arg));
  if (hits.length > 1) die(`ambiguous task ${arg}: ${hits.map((h) => h.meta.id).join(' ')}`);
  if (hits.length === 1) return { id: hits[0].meta.card_id, short: hits[0].meta.id };
  if (/^([A-Za-z0-9]{8}|[a-f0-9]{24})$/.test(arg)) return { id: arg, short: arg };
  die(`no task ${arg} in the cache: run pull`);
}

async function op(op, a) {
  let r, title;
  if (op === 'add') {
    title = one(a[0]); if (!title) die('add needs a title');
    const o = opts(a.slice(1)), lists = await boardLists();
    const body = { idList: (o.list ? findList(lists, o.list) : todoList(lists)).id, name: title };
    if (o.due) body.due = o.due;
    if (o.desc) body.desc = o.desc;
    const map = readMap();
    if (map.me?.id && map.boards?.[B]?.members?.some((m) => m.id === map.me.id)) body.idMembers = [map.me.id];
    const c = await trello('POST', '/cards', body);
    r = { id: c.id, short: c.shortLink };
  } else {
    r = resolveCard(a[0]);
    const path = `/cards/${r.id}`;
    if (op === 'item-add') {
      const text = one(a[1]); if (!text) die('item add needs text');
      let cl = (await trello('GET', `${path}/checklists?fields=name`))[0];
      if (!cl) cl = await trello('POST', `${path}/checklists`, { name: 'Checklist' });
      await trello('POST', `/checklists/${cl.id}/checkItems`, { name: text });
    } else if (op === 'check' || op === 'uncheck') {
      await trello('PUT', `${path}/checkItem/${itemId(a[1])}`, { state: op === 'check' ? 'complete' : 'incomplete' });
    } else if (op === 'rename') {
      const t = one(a[1]); if (!t) die('rename needs a title');
      await trello('PUT', path, { name: t });
    } else if (op === 'move') {
      if (!a[1]) die('move needs a list');
      await trello('PUT', path, { idList: findList(await boardLists(), a[1]).id });
    } else if (op === 'comment') {
      if (!a[1]) die('comment needs text');
      await trello('POST', `${path}/actions/comments`, { text: a[1] });
    } else if (op === 'link') {
      const body = { url: httpUrl(a[1]) };
      if (one(a[2])) body.name = one(a[2]);
      await trello('POST', `${path}/attachments`, body);
    } else if (op === 'done') {
      const d = doneList(await boardLists());
      await trello('PUT', path, d ? { idList: d.id } : { closed: true });
    } else if (op === 'reopen') {
      const lists = await boardLists(), body = { closed: false };
      if (doneList(lists)) body.idList = todoList(lists).id;
      await trello('PUT', path, body);
    } else die(`unknown command ${op}`);
  }
  try { await refresh(r.id); } catch { console.log(`remote ok (${r.short}), local refresh failed: run pull`); return; }
  console.log(op === 'add' ? `added ${r.short} ${title}` : `ok ${r.short}`);
}

// ---- discovery: structure and a derived card style, never card names or descriptions ----
function style(cards, fields) {
  const n = cards.length, pct = (k) => `${n ? Math.round((100 * k) / n) : 0}%`, cnt = (f) => cards.filter(f).length;
  let title = 'free text';
  for (const [name, re] of [['bracket prefix', /^\[[^\]]+\]\s/], ['ticket key', /^[A-Z][A-Z0-9]+-\d+\b/], ['colon prefix', /^[^:\s][^:]{0,24}:\s/]]) {
    const k = cnt((c) => re.test(c.name || ''));
    if (k > 0 && k * 2 >= n) { title = `${name} ${pct(k)}`; break; }
  }
  const ref = fields.find((f) => /\b(ref|reference|link|url|ticket)\b/i.test(f.name));
  const refRate = ref ? `${ref.name} ${pct(cnt((c) => (c.customFieldItems || []).some((i) => i.idCustomField === ref.id && i.value && Object.values(i.value).some(Boolean))))}` : 'none';
  return { sampled: n, title_pattern: title, checklist_rate: pct(cnt((c) => (c.idChecklists || []).length > 0)),
    due_rate: pct(cnt((c) => c.due)), start_rate: pct(cnt((c) => c.start)), label_rate: pct(cnt((c) => (c.idLabels || []).length > 0)), ref_field: refRate };
}
async function discover(ids) {
  const me = await trello('GET', '/members/me?fields=username');
  const boards = {};
  for (const id of ids) {
    if (!/^[A-Za-z0-9]+$/.test(id)) die(`bad board id ${id}`);
    const get = (p) => trello('GET', `/boards/${id}${p}`);
    const b = await get('?fields=name');
    const lists = await get('/lists?filter=open&fields=name,pos');
    const labels = await get('/labels?fields=name,color&limit=1000');
    const fields = await get('/customFields');
    const members = await get('/members?fields=username');
    const cards = await get('/cards?limit=20&fields=name,due,start,idChecklists,idLabels&customFieldItems=true');
    boards[id] = { name: one(b.name), lists: lists.slice(0, 50).map((l) => ({ id: l.id, name: one(l.name) })), lists_total: lists.length,
      labels: labels.map((l) => ({ id: l.id, name: one(l.name), color: l.color ?? '' })),
      custom_fields: fields.map((f) => ({ id: f.id, name: one(f.name), type: f.type, options: (f.options || []).map((o) => ({ id: o.id, value: one(o.value?.text) })) })),
      members: members.map((m) => ({ id: m.id, username: m.username })), card_style: style(cards, fields) };
  }
  const at = new Date().toISOString();
  const map = { generated_at: at, me: { id: me.id, username: me.username }, boards };
  const md = ['<!-- generated from trello.json by kaito-tasks.sh discover; do not edit -->', '# Trello board map', '',
    `Discovered ${at}. Caps: at most 50 lists per board; card style comes from the last 20 cards. No card names or descriptions are stored.`,
    `Me: ${me.username} (${me.id})`];
  for (const [id, b] of Object.entries(boards)) {
    const s = b.card_style, j = (xs) => xs.join(', ') || 'none';
    md.push('', `## ${b.name} (${id})`, '',
      `- Lists: ${j(b.lists.map((l) => `${l.name} (${l.id})`))}${b.lists_total > 50 ? ` (first 50 of ${b.lists_total})` : ''}`,
      `- Labels: ${j(b.labels.map((l) => `${l.name || '(no name)'} ${l.color} (${l.id})`))}`,
      `- Custom fields: ${b.custom_fields.map((f) => `${f.name} ${f.type} (${f.id})${f.options.length ? ': ' + f.options.map((o) => `${o.value} (${o.id})`).join(', ') : ''}`).join('; ') || 'none'}`,
      `- Members: ${j(b.members.map((m) => `${m.username} (${m.id})`))}`,
      `- Card style (${s.sampled} cards): titles ${s.title_pattern}; checklists ${s.checklist_rate}; due ${s.due_rate}; start ${s.start_rate}; labels ${s.label_rate}; Ref-like field ${s.ref_field}`);
  }
  const dir = join(M, 'managers'), mdFile = join(dir, 'trello.md');
  mkdirSync(dir, { recursive: true });
  writeFileSync(`${mapFile}.${process.pid}.tmp`, JSON.stringify(map, null, 2) + '\n');
  writeFileSync(`${mdFile}.${process.pid}.tmp`, md.join('\n') + '\n');
  renameSync(`${mapFile}.${process.pid}.tmp`, mapFile);
  renameSync(`${mdFile}.${process.pid}.tmp`, mdFile);
  console.log(`discovered ${ids.length} board(s): ${mapFile}`);
}

export default {
  remote: true,     // list warns when there is no cache yet
  indexDone: true,  // the index shows every open card, Done list included
  isDone: (t) => /^done$/i.test(t.meta.list || ''),
  where: (t) => t.meta.list,
  redact,
  commands: {
    boards: async () => { for (const b of await trello('GET', '/members/me/boards?filter=open&fields=name')) console.log(`${b.id} ${one(b.name)}`); },
    'board-name': async ([id]) => console.log(one((await trello('GET', `/boards/${id}?fields=name`)).name)),
    me: async () => console.log((await trello('GET', '/members/me?fields=username')).username),
    discover,
    pull,
  },
  op,
};
