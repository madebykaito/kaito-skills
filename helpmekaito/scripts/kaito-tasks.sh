#!/bin/sh
# Tasks for the current project. Trello: the board is the truth, tasks/<slug>/ is a read cache.
# Obsidian: one note per task under tasks/<slug>/, no remote. Other managers go through their MCP.
# Usage: kaito-tasks.sh status | login | boards | consent yes|no <boardId>... | discover | map <boardId> | pull | list
#   add "<title>" [--list <name|id>] [--due <iso>] [--desc <text>] | item add <task> "<text>"
#   check|uncheck <task> <item> | rename <task> "<title>" | move <task> <list|status>
#   comment <task> "<text>" | done <task> | reopen <task>
set +x  # never trace: credentials are read below
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
K="${KAITO_HOME:-$HOME/.kaito}"
CFG="$K/config.json"
USAGE="usage: kaito-tasks.sh status|login|boards|consent|discover|map|pull|list|add|item add|check|uncheck|rename|move|comment|done|reopen"
cfg() { node "$here/kaito-json.mjs" get "$CFG" "$1" 2>/dev/null | sed 's/^"\(.*\)"$/\1/'; }
die() { echo "kaito-tasks: $*" >&2; exit 1; }

mgr=$(cfg tasks.manager)
cmd=${1:-}
case "$mgr" in
  trello|obsidian) ;;
  "") [ "$cmd" = status ] || die "no task manager set: run setup"
      echo "manager: none"; echo "onboarding: $(cfg tasks.state || :)"; exit 0 ;;
  *) echo "use the $mgr MCP; see references/tasks.md"; exit 0 ;;
esac

M=$(sh "$here/kaito-mem.sh" dir)
p=$(git rev-parse --show-toplevel 2>/dev/null) || p=$(pwd)
p=$(cd "$p" && pwd -P)
S=$(sh "$here/kaito-codegraph.sh" slug "$p")
pf="$M/projects/$S.md"
D="$M/tasks/$S"
board=$(grep '^board: ' "$pf" 2>/dev/null | head -n1) || board=""
B=$(printf %s "$board" | awk '{print $3}')
export M S D B KT="$here/kaito-trello.mjs" MGR="$mgr"

# Credentials: env pair, else ~/.kaito/.env, else ~/.config/trello/.env. Key and token from one source, read as data.
envval() { sed -n "s/^\(export \)\{0,1\}$1=//p" "$2" 2>/dev/null | head -n1 | tr -d '\r' | sed "s/^\"\(.*\)\"\$/\1/; s/^'\(.*\)'\$/\1/"; }
creds() {
  if [ -n "${TRELLO_KEY:-}" ] && [ -n "${TRELLO_TOKEN:-}" ]; then
    KAITO_TRELLO_KEY=$TRELLO_KEY; KAITO_TRELLO_TOKEN=$TRELLO_TOKEN; SRC=env; return 0
  fi
  for f in "$K/.env" "$HOME/.config/trello/.env"; do
    KAITO_TRELLO_KEY=$(envval TRELLO_KEY "$f"); KAITO_TRELLO_TOKEN=$(envval TRELLO_TOKEN "$f")
    if [ -n "$KAITO_TRELLO_KEY" ] && [ -n "$KAITO_TRELLO_TOKEN" ]; then SRC=$f; return 0; fi
  done
  KAITO_TRELLO_KEY=""; KAITO_TRELLO_TOKEN=""; return 1
}
need_creds() {
  creds || die "no Trello credentials: run 'sh $here/kaito-tasks.sh login' in a terminal"
  export KAITO_TRELLO_KEY KAITO_TRELLO_TOKEN  # node gets them from env, never argv
}
need_board() { [ -n "$B" ] || die "no board mapped for this project: run kaito-tasks.sh boards, then map <boardId>"; }

# One memory writer at a time, same lock as kaito-mem.sh. ponytail: a lock left by a killed run is taken over after 2s.
mlock() {
  [ -w "$M" ] || return 1
  i=0; until mkdir "$M/.lock" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -eq 20 ]; then rmdir "$M/.lock" 2>/dev/null || :; fi
    [ "$i" -le 21 ] || return 1
    sleep 0.1
  done
  trap 'rmdir "$M/.lock" 2>/dev/null || :' EXIT
}

# The node side: Trello calls, cache rendering, Obsidian notes. Local writes hold tasks/.<slug>.lock, never across a fetch.
J() {
node --input-type=module - "$@" <<'JS'
import { readFileSync, writeFileSync, mkdirSync, renameSync, rmSync, rmdirSync, readdirSync, statSync, existsSync, utimesSync, copyFileSync, unlinkSync } from 'node:fs';
import { join, resolve, sep } from 'node:path';
import { randomBytes } from 'node:crypto';
import { pathToFileURL } from 'node:url';
const { trello, redact } = await import(pathToFileURL(process.env.KT).href);
const { M, D, B, S, MGR } = process.env;
const [cmd, ...args] = process.argv.slice(2);
const die = (m) => { console.error(`kaito-tasks: ${m}`); process.exit(1); };
const one = (s) => String(s ?? '').replace(/[\r\n]+/g, ' ').trim();
const q = (v) => JSON.stringify(one(v));  // every frontmatter value is a quoted string; JSON escapes are valid YAML
const fm = (o) => '---\n' + Object.entries(o).map(([k, v]) => `${k}: ${q(v)}`).join('\n') + '\n---\n';
const parse = (text) => {
  const m = text.match(/^---\n([\s\S]*?)\n---\n?/), meta = {};
  if (m) for (const l of m[1].split('\n')) {
    const x = l.match(/^(\w+): (.*)$/);
    if (x) { try { meta[x[1]] = JSON.parse(x[2]); } catch { meta[x[1]] = x[2]; } }
  }
  return { meta, body: m ? text.slice(m[0].length) : text };
};
const slug = (t) => String(t).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+/, '').slice(0, 50).replace(/-+$/, '') || 'task';
const inside = (dir, f) => {
  const p = resolve(dir, f);
  if (!p.startsWith(resolve(dir) + sep)) die('refusing a path outside the tasks folder');
  return p;
};
const atomic = (file, text) => { const t = `${file}.${process.pid}.tmp`; writeFileSync(t, text); renameSync(t, file); };
const rnd = (n) => [...randomBytes(n)].map((b) => 'abcdefghijklmnopqrstuvwxyz0123456789'[b % 36]).join('');
const openItems = (body) => (body.match(/^- \[ \] .*<!-- id:\S+ -->$/gm) || []).length;
const taskFiles = (dir = D) => existsSync(dir)
  ? readdirSync(dir).filter((f) => f.endsWith('.md') && f !== 'index.md').map((f) => ({ f, path: join(dir, f), ...parse(readFileSync(join(dir, f), 'utf8')) }))
  : [];
const isDone = (t) => (MGR === 'trello' ? /^done$/i.test(t.meta.list || '') : t.meta.status === 'done');
const where = (t) => (MGR === 'trello' ? t.meta.list : t.meta.status);
function writeIndex(dir = D) {
  mkdirSync(dir, { recursive: true });
  const rows = taskFiles(dir).filter((t) => MGR === 'trello' || !isDone(t))
    .map((t) => `- [[${t.f.slice(0, -3)}]] ${where(t)} · ${one(t.meta.title)} (${openItems(t.body)} open)`);
  atomic(join(dir, 'index.md'), `<!-- generated by kaito-tasks.sh; edit tasks through helpmekaito -->\n# Tasks\n\n${rows.join('\n')}\n`);
}

// Lock around local writes only. ponytail: a lock a killed run left is taken over after 5s.
let held = '';
process.on('exit', () => { if (held) try { rmdirSync(held); } catch {} });
function locked(fn) {
  const L = join(M, 'tasks', `.${S}.lock`);
  mkdirSync(join(M, 'tasks'), { recursive: true });
  for (let i = 0; ; i++) {
    try { mkdirSync(L); break; } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      if (i === 50) try { rmdirSync(L); } catch {}
      if (i > 51) die('tasks folder is busy, try again');
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
    }
  }
  held = L;
  try { return fn(); } finally { rmdirSync(L); held = ''; }
}

// ---- Trello ----
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
  const tmp = join(M, 'tasks', `.${S}.new.${process.pid}`);
  try {
    mkdirSync(tmp, { recursive: true });
    for (const c of cards) writeCard(tmp, c, names, at);
    writeIndex(tmp);
  } catch (e) { rmSync(tmp, { recursive: true, force: true }); throw e; }
  locked(() => {
    if (existsSync(D)) {
      const cdir = join(tmp, 'conflicts');
      for (const t of taskFiles(D)) {  // edited after its sync: keep the edit as a conflict copy
        const synced = Date.parse(t.meta.synced_at);
        if (!synced || Math.floor(statSync(t.path).mtimeMs / 1000) <= Math.floor(synced / 1000)) continue;
        mkdirSync(cdir, { recursive: true });
        const name = `${t.f.slice(0, -3)}.conflict.md`;
        copyFileSync(t.path, join(cdir, name));
        console.error(`warning: ${t.f} was edited locally; your copy is in conflicts/${name}. Edit tasks through helpmekaito.`);
      }
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
    for (const t of taskFiles(D)) if (t.meta.card_id === c.id) unlinkSync(t.path);
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
const itemId = (x) => (/^[A-Za-z0-9-]+$/.test(x || '') ? x : die(`bad item id ${x ?? ''}`));
function opts(rest) {
  const o = {};
  for (let i = 0; i < rest.length; i += 2) {
    const k = rest[i].replace(/^--/, '');
    if (!['list', 'due', 'desc'].includes(k) || rest[i + 1] === undefined) die(`unknown option ${rest[i]}`);
    o[k] = rest[i + 1];
  }
  if (o.due && Number.isNaN(Date.parse(o.due))) die(`bad due date ${o.due}`);
  return o;
}

async function trelloOp(op, a) {
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

// ---- Obsidian: the notes are the source ----
const STATUS = ['todo', 'doing', 'done'];
function obsOp(op, a) {
  const arch = join(D, 'archive');
  const find = (x) => {
    if (!/^[a-z0-9-]+$/.test(x || '')) die(`bad task id ${x ?? ''}`);
    const ts = [...taskFiles(D), ...taskFiles(arch)].filter((t) => /^t-\d{8}-[a-z0-9]{4}$/.test(t.meta.id || ''));
    const exact = ts.find((t) => t.meta.id === x);
    const hits = exact ? [exact] : ts.filter((t) => t.meta.id.startsWith(x));
    if (hits.length > 1) die(`ambiguous task ${x}: ${hits.map((h) => h.meta.id).join(' ')}`);
    return hits[0] || die(`no task ${x}`);
  };
  const save = (t, meta, body, dir) => {
    meta.updated = new Date().toISOString();
    mkdirSync(dir, { recursive: true });
    const f = inside(dir, `${meta.id}-${slug(meta.title)}.md`);
    atomic(f, fm(meta) + body.replace(/^\n+/, '').replace(/\s*$/, '\n'));
    if (t && t.path !== f) unlinkSync(t.path);
  };
  if (op === 'move' && !STATUS.includes(a[1])) die(`move needs a status: ${STATUS.join('|')}`);
  locked(() => {
    if (op === 'add') {
      const title = one(a[0]); if (!title) die('add needs a title');
      const o = opts(a.slice(1));
      if (o.list && !STATUS.includes(o.list)) die(`--list takes a status: ${STATUS.join('|')}`);
      const d = new Date(), ymd = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
      let id; do id = `t-${ymd}-${rnd(4)}`; while (existsSync(D) && readdirSync(D).some((f) => f.startsWith(id)));
      const now = d.toISOString();
      save(null, { id, title, status: o.list || 'todo', due: o.due || '', created: now, updated: now }, o.desc ? one(o.desc) : '', D);
      console.log(`added ${id} ${title}`);
    } else {
      const t = find(a[0]), meta = { ...t.meta };
      let body = t.body, dir = t.path.startsWith(arch + sep) ? arch : D;
      if (op === 'item-add') {
        const text = one(a[1]); if (!text) die('item add needs text');
        let iid; do iid = `i-${rnd(4)}`; while (body.includes(`<!-- id:${iid} -->`));
        body = `${body.trimEnd()}\n${openItems(body) || /<!-- id:i-/.test(body) ? '' : '\n### Items\n'}- [ ] ${text} <!-- id:${iid} -->\n`;
      } else if (op === 'check' || op === 'uncheck') {
        const iid = itemId(a[1]), re = new RegExp(`^- \\[[ x]\\] (.*) <!-- id:${iid} -->$`, 'm');
        if (!re.test(body)) die(`no item ${iid} in ${meta.id}`);
        body = body.replace(re, `- [${op === 'check' ? 'x' : ' '}] $1 <!-- id:${iid} -->`);
      } else if (op === 'rename') {
        meta.title = one(a[1]); if (!meta.title) die('rename needs a title');
      } else if (op === 'comment') {
        const text = one(a[1]); if (!text) die('comment needs text');
        body = `${body.trimEnd()}\n\n> ${new Date().toISOString().slice(0, 10)} ${text}\n`;
      } else if (op === 'done' || (op === 'move' && a[1] === 'done')) {
        meta.status = 'done'; dir = arch;
      } else if (op === 'reopen' || op === 'move') {
        meta.status = op === 'move' ? a[1] : 'todo'; dir = D;
      } else die(`unknown command ${op}`);
      save(t, meta, body, dir);
      console.log(`ok ${meta.id}`);
    }
    writeIndex();
  });
}

function list() {
  const ts = taskFiles(D).filter((t) => !isDone(t));
  if (MGR === 'trello' && !existsSync(D)) console.error('no cache yet: run kaito-tasks.sh pull');
  for (const t of ts) console.log(`${t.meta.id} ${where(t)} ${one(t.meta.title)} (${openItems(t.body)} open)`);
}

try {
  if (cmd === 'boards') for (const b of await trello('GET', '/members/me/boards?filter=open&fields=name')) console.log(`${b.id} ${one(b.name)}`);
  else if (cmd === 'board-name') console.log(one((await trello('GET', `/boards/${args[0]}?fields=name`)).name));
  else if (cmd === 'me') console.log((await trello('GET', '/members/me?fields=username')).username);
  else if (cmd === 'discover') await discover(args);
  else if (cmd === 'pull') await pull();
  else if (cmd === 'list') list();
  else if (cmd === 'op') await (MGR === 'trello' ? trelloOp(args[0], args.slice(1)) : obsOp(args[0], args.slice(1)));
  else die(`unknown command ${cmd}`);
} catch (e) {
  console.error(`kaito-tasks: ${redact(e.message)}`);
  process.exit(1);
}
JS
}

case "$cmd" in
  status)
    echo "manager: $mgr"
    if [ "$mgr" = trello ]; then
      if creds; then echo "credentials: yes ($SRC)"; else echo "credentials: no"; fi
      echo "${board:-board: none}"
    else echo "notes: $D"; fi
    c=$(cfg tasks.discovery.consent)
    if [ -n "$c" ]; then echo "discovery: $c $(cfg tasks.discovery.at) ($(node "$here/kaito-json.mjs" each "$CFG" tasks.discovery.boards | tr '\n' ' ' | sed 's/ $//'))"
    else echo "discovery: not asked"; fi
    s=$(cfg tasks.state); echo "onboarding: ${s:-pending}"
    ;;
  login)
    [ "$mgr" = trello ] || die "login is for Trello; the manager is $mgr"
    [ -t 0 ] && [ -t 1 ] || die "login reads secrets, so run it in a terminal: sh $here/kaito-tasks.sh login"
    cat <<EOF
Trello needs an API key and a token.
  1. Open https://trello.com/power-ups/admin and make a new Power-Up (any name, any workspace).
  2. Open it, go to API key, and generate a new API key. Copy the key.
  3. On that page, follow the link to generate a token (the authorize link next to the key). Allow, then copy the token.
They are saved to $K/.env (mode 600). Nothing is echoed.
The Trello MCP is optional and separate: add it from your agent's MCP or connector settings (see references/tasks.md).

EOF
    old=$(stty -g)
    trap 'stty "$old" 2>/dev/null || :' EXIT
    trap 'stty "$old" 2>/dev/null || :; exit 130' INT TERM
    stty -echo
    printf "Trello API key: "; IFS= read -r key || key=""; echo
    printf "Trello token: "; IFS= read -r tok || tok=""; echo
    stty "$old"
    case "$key$tok" in *[!A-Za-z0-9]*) die "that does not look like a Trello key and token; nothing saved" ;; esac
    [ -n "$key" ] && [ -n "$tok" ] || die "key and token are both needed; nothing saved"
    u=$(KAITO_TRELLO_KEY=$key KAITO_TRELLO_TOKEN=$tok J me 2>/dev/null) || die "Trello did not accept that key and token; nothing saved"
    (
      umask 077; mkdir -p "$K"; t="$K/.env.$$.tmp"
      { grep -v -e '^TRELLO_KEY=' -e '^TRELLO_TOKEN=' -e '^export TRELLO_KEY=' -e '^export TRELLO_TOKEN=' "$K/.env" 2>/dev/null || :
        printf 'TRELLO_KEY=%s\nTRELLO_TOKEN=%s\n' "$key" "$tok"; } > "$t"
      chmod 600 "$t"; mv "$t" "$K/.env"
    )
    node "$here/kaito-json.mjs" set "$CFG" tasks.steps.credentials true
    echo "saved Trello credentials for $u to $K/.env"
    ;;
  boards) need_creds; J boards ;;
  consent)
    case "${2:-}" in yes|no) ;; *) die "usage: kaito-tasks.sh consent yes|no <boardId>..." ;; esac
    a=$2; shift 2
    [ "$a" = no ] || [ $# -gt 0 ] || die "consent yes needs the board ids to discover"
    list=""; for b in "$@"; do
      case "$b" in ""|*[!A-Za-z0-9]*) die "bad board id $b" ;; esac
      list="$list${list:+,}\"$b\""
    done
    node "$here/kaito-json.mjs" set "$CFG" tasks.discovery "{\"consent\":\"$a\",\"boards\":[$list],\"at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
    node "$here/kaito-json.mjs" set "$CFG" tasks.steps.discovery true
    echo "discovery consent: $a${list:+ for $*}"
    ;;
  discover)
    [ "$mgr" = trello ] || die "discover is for Trello"
    [ "$(cfg tasks.discovery.consent)" = yes ] || die "no discovery consent: ask first, then run kaito-tasks.sh consent yes <boardId>..."
    bs=$(node "$here/kaito-json.mjs" each "$CFG" tasks.discovery.boards)
    [ -n "$bs" ] || die "consent lists no boards"
    need_creds
    # shellcheck disable=SC2086  # ids are checked to [A-Za-z0-9] by consent
    J discover $bs
    ;;
  map)
    [ "$mgr" = trello ] || die "map is for Trello"
    id=${2:-}; case "$id" in ""|*[!A-Za-z0-9]*) die "usage: kaito-tasks.sh map <boardId>" ;; esac
    need_creds
    name=$(J board-name "$id")  # fetched before the lock: never hold it across a network call
    (
      mkdir -p "$M/projects"; mlock
      [ -e "$pf" ] || printf "%s\n" "- projects/$S.md $p" >> "$M/MEMORY.md"
      { grep -v '^board:' "$pf" 2>/dev/null || :; echo "board: trello $id $name"; } > "$pf.$$.tmp"
      mv "$pf.$$.tmp" "$pf"
    ) || die "could not write $pf"
    if [ -x "$here/kaito-obsidian.sh" ]; then "$here/kaito-obsidian.sh" push "projects/$S.md" >/dev/null 2>&1 || :; fi
    echo "board: trello $id $name"
    ;;
  pull)
    if [ "$mgr" = obsidian ]; then echo "obsidian notes are the source; nothing to pull"; exit 0; fi
    need_board; need_creds; J pull ;;
  list) J list ;;
  add|check|uncheck|rename|move|comment|done|reopen|item)
    op=$cmd; shift
    if [ "$op" = item ]; then [ "${1:-}" = add ] || die "usage: kaito-tasks.sh item add <task> \"<text>\""; op=item-add; shift; fi
    if [ "$mgr" = trello ]; then need_board; need_creds; fi
    J op "$op" "$@"
    ;;
  *) echo "$USAGE" >&2; exit 2 ;;
esac
