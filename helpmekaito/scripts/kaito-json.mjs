// Tiny JSON editor: node kaito-json.mjs get|set|del|add|rm|each <file> <dot.path> [json]
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const [cmd, file, path = '', raw] = process.argv.slice(2);
const keys = path.split('.').filter(Boolean);
let data = {};
const bad = () => {
  if (cmd === 'get') process.exit(0);
  console.error('file is not valid JSON, not touching it');
  process.exit(1);
};
try {
  const text = readFileSync(file, 'utf8');
  if (text.trim()) data = JSON.parse(text);
} catch (e) {
  if (e.code !== 'ENOENT') bad();
}
if (typeof data !== 'object' || data === null || Array.isArray(data)) bad();
const save = () => {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
};
const last = keys.pop();

if (cmd === 'get') {
  const v = [...keys, last].reduce((o, k) => o?.[k], data);
  if (v !== undefined) console.log(JSON.stringify(v));
} else if (cmd === 'each') {
  const v = [...keys, last].reduce((o, k) => o?.[k], data);
  if (Array.isArray(v)) for (const x of v) console.log(typeof x === 'string' ? x : JSON.stringify(x));
} else if (cmd === 'add' || cmd === 'rm') {
  // add appends to an array unless an equal item is there; rm drops equal items.
  let o = data;
  for (const k of keys) o = typeof o[k] === 'object' && o[k] !== null ? o[k] : (o[k] = {});
  const item = JSON.parse(raw), s = JSON.stringify(item);
  const arr = Array.isArray(o[last]) ? o[last] : [];
  if (cmd === 'add') { if (!arr.some((x) => JSON.stringify(x) === s)) o[last] = [...arr, item]; }
  else if (Array.isArray(o[last])) o[last] = arr.filter((x) => JSON.stringify(x) !== s);
  save();
} else if (cmd === 'set') {
  let o = data;
  for (const k of keys) o = typeof o[k] === 'object' && o[k] !== null ? o[k] : (o[k] = {});
  o[last] = JSON.parse(raw);
  save();
} else if (cmd === 'del') {
  let o = data;
  for (const k of keys) o = o?.[k];
  if (o && typeof o === 'object') delete o[last];
  save();
} else {
  console.error('usage: kaito-json.mjs get|set|del|add|rm|each <file> <dot.path> [json]');
  process.exit(2);
}
