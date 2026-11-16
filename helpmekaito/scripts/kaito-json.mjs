// Tiny JSON editor: node kaito-json.mjs get|set|del|add|rm|each|check <file> <dot.path> [json]
import { readFileSync, writeFileSync, mkdirSync, renameSync, realpathSync, readlinkSync, statSync, chmodSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const [cmd, file, path = '', raw] = process.argv.slice(2);
const keys = path.split('.').filter(Boolean);
let data = {};
const bad = () => {
  if (cmd === 'get') process.exit(0);
  console.error('not valid JSON for this change, not touching it');
  process.exit(1);
};
try {
  const text = readFileSync(file, 'utf8');
  if (text.trim()) data = JSON.parse(text);
} catch (e) {
  if (e.code !== 'ENOENT') bad();
}
if (typeof data !== 'object' || data === null || Array.isArray(data)) bad();
// Write a temp file and rename it over the target, so a killed run never leaves half a file.
const save = () => {
  let target = file, mode;
  try { target = realpathSync(file); mode = statSync(target).mode & 0o777; }  // a symlinked file stays a symlink
  catch { try { target = resolve(dirname(file), readlinkSync(file)); } catch {} }  // so does a dangling one
  mkdirSync(dirname(target), { recursive: true });
  const tmp = `${target}.${process.pid}.tmp`;
  writeFileSync(tmp, JSON.stringify(data, null, 2) + '\n');
  if (mode !== undefined) chmodSync(tmp, mode);  // exact mode, whatever the umask
  renameSync(tmp, target);
};
const last = keys.pop();
// Walk to the parent, creating missing objects. A scalar in the way is the user's value: refuse.
const parent = () => {
  let o = data;
  for (const k of keys) {
    if (o[k] === undefined) o[k] = {};
    else if (typeof o[k] !== 'object' || o[k] === null) bad();
    o = o[k];
  }
  return o;
};

if (cmd === 'get') {
  const v = [...keys, last].reduce((o, k) => o?.[k], data);
  if (v !== undefined) console.log(JSON.stringify(v));
} else if (cmd === 'each') {
  const v = [...keys, last].reduce((o, k) => o?.[k], data);
  if (Array.isArray(v)) for (const x of v) console.log(typeof x === 'string' ? x : JSON.stringify(x));
} else if (cmd === 'add' || cmd === 'rm') {
  // add appends to an array unless an equal item is there; rm drops equal items.
  const item = JSON.parse(raw), s = JSON.stringify(item);
  if (cmd === 'rm') {  // never creates or replaces anything on the way down
    const o = keys.reduce((p, k) => p?.[k], data);
    if (!Array.isArray(o?.[last])) process.exit(0);
    o[last] = o[last].filter((x) => JSON.stringify(x) !== s);
  } else {
    const o = parent();
    if (o[last] !== undefined && !Array.isArray(o[last])) bad();
    const arr = o[last] ?? [];
    if (!arr.some((x) => JSON.stringify(x) === s)) o[last] = [...arr, item];
  }
  save();
} else if (cmd === 'set') {
  parent()[last] = JSON.parse(raw);
  save();
} else if (cmd === 'del') {
  let o = data;
  for (const k of keys) o = o?.[k];
  if (o && typeof o === 'object') delete o[last];
  save();
} else if (cmd !== 'check') {  // check: exit 0 if the file is missing or parses
  console.error('usage: kaito-json.mjs get|set|del|add|rm|each|check <file> <dot.path> [json]');
  process.exit(2);
}
