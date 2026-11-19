// A project's trackers, kept as lines in <memory>/projects/<slug>.md:
//   tracker: <manager> <id> <name> | role=<official|personal> | tracking=<always|never|ask> | note=<text>
//   tracking: never            (project level: this project is not tracked anywhere, do not ask)
// An older "board: <manager> <id> <name>" line reads as one official tracker; "board: none" reads as tracking: never.
// node kaito-trackers.mjs <project-file> list | select [manager] | add <manager> <id> <name> [key=value...]
//   | set <manager> key=value... | rm <manager> | project never|ask
// Callers hold the memory lock around the writing commands.
import { readFileSync, writeFileSync, renameSync } from 'node:fs';

const [file, cmd, ...args] = process.argv.slice(2);
const die = (m) => { console.error(`kaito-tasks: ${m}`); process.exit(1); };
const SCRIPTED = ['trello', 'plane', 'obsidian'];  // managers kaito-tasks.sh drives itself; the rest go through their MCP
const KEYS = { role: ['official', 'personal'], tracking: ['always', 'never', 'ask'] };
const clean = (s) => String(s ?? '').replace(/[\r\n|]+/g, ' ').trim();

const lines = (() => { try { return readFileSync(file, 'utf8').split('\n'); } catch { return []; } })();
function parse() {
  const out = [];
  let project = '';
  for (const l of lines) {
    let m;
    if ((m = l.match(/^tracking: (never|ask)\s*$/))) project = m[1];
    else if (/^board: none\s*$/.test(l)) project = 'never';
    else if ((m = l.match(/^(tracker|board): ([a-z][a-z0-9-]*) (\S+) ?(.*)$/))) {
      const [name, ...attrs] = m[4].split(' | ');
      const t = { manager: m[2], id: m[3], name: name.trim(), role: 'official', tracking: 'ask', note: '', legacy: m[1] === 'board' };
      for (const a of attrs) { const [k, ...v] = a.split('='), key = k.trim(); if (['role', 'tracking', 'note'].includes(key)) t[key] = v.join('=').trim(); }
      out.push(t);
    }
  }
  return { trackers: out, project };
}
const show = (t) => `tracker: ${t.manager} ${t.id} ${t.name} | role=${t.role} | tracking=${t.tracking}${t.note ? ` | note=${t.note}` : ''}`;
function write({ trackers, project }) {
  const rest = lines.filter((l) => !/^(tracker|board|tracking): /.test(l));
  while (rest.length && rest[rest.length - 1] === '') rest.pop();
  const head = [...trackers.map(show), ...(project ? [`tracking: ${project}`] : [])];
  const tmp = `${file}.${process.pid}.tmp`;
  writeFileSync(tmp, [...head, ...rest].join('\n') + '\n');
  renameSync(tmp, file);
}
function apply(t, pairs) {
  for (const p of pairs) {
    const [k, ...v] = p.split('='), val = clean(v.join('='));
    if (k === 'note') t.note = val;
    else if (KEYS[k]) { if (!KEYS[k].includes(val)) die(`${k} is one of: ${KEYS[k].join(', ')}`); t[k] = val; }
    else die(`unknown setting ${k}: use role=, tracking= or note=`);
  }
  if (/((api[_ -]?key|token|passw(or)?d|secret)\s*[:=]|bearer\s+[a-z0-9._-]{12,})/i.test(t.note)) die('refusing to store what looks like a secret');
}
const mgrOk = (m) => (/^[a-z][a-z0-9-]*$/.test(m || '') ? m : die(`bad manager ${m ?? ''}`));

const st = parse();
if (cmd === 'list') {
  for (const t of st.trackers) console.log(show(t));
  if (st.project) console.log(`tracking: ${st.project}`);
} else if (cmd === 'select') {
  // Which tracker a command acts on: the named one, else the first scripted one, else the first.
  const want = args[0] || '';
  const t = want ? st.trackers.find((x) => x.manager === want) || die(`this project has no ${want} tracker: kaito-tasks.sh tracker list`)
    : st.trackers.find((x) => SCRIPTED.includes(x.manager)) || st.trackers[0];
  const scripted = st.trackers.filter((x) => SCRIPTED.includes(x.manager)).map((x) => x.manager);
  console.log([t?.manager ?? '', t?.id ?? '', st.project === 'never' ? 'never' : t?.tracking ?? st.project ?? '', scripted.join(' ')].join('\n'));
} else if (cmd === 'add') {
  const [m, id, name, ...pairs] = args;
  mgrOk(m);
  if (!/^[A-Za-z0-9/_.-]+$/.test(id || '')) die(`bad tracker id ${id ?? ''}`);
  const old = st.trackers.find((x) => x.manager === m);
  const t = { manager: m, id, name: clean(name) || m, role: old?.role ?? 'official', tracking: old?.tracking ?? 'ask', note: old?.note ?? '' };
  apply(t, pairs);
  st.trackers = [...st.trackers.filter((x) => x.manager !== m), t];
  if (st.project === 'never') st.project = '';  // adding a tracker turns project tracking back on
  write(st);
  console.log(show(t));
} else if (cmd === 'set') {
  const t = st.trackers.find((x) => x.manager === mgrOk(args[0])) || die(`this project has no ${args[0]} tracker`);
  if (args.length < 2) die('usage: kaito-tasks.sh tracker set <manager> role=|tracking=|note=');
  apply(t, args.slice(1));
  write(st);
  console.log(show(t));
} else if (cmd === 'rm') {
  if (!st.trackers.some((x) => x.manager === mgrOk(args[0]))) die(`this project has no ${args[0]} tracker`);
  st.trackers = st.trackers.filter((x) => x.manager !== args[0]);
  write(st);
  console.log(`removed ${args[0]}`);
} else if (cmd === 'project') {
  if (!['never', 'ask'].includes(args[0])) die('usage: kaito-tasks.sh tracking never|ask');
  st.project = args[0] === 'ask' ? '' : 'never';
  write(st);
  console.log(`tracking: ${args[0]}`);
} else die('usage: kaito-trackers.mjs <project-file> list|select|add|set|rm|project');
