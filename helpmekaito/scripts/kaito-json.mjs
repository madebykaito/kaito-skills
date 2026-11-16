// Tiny JSON editor: node kaito-json.mjs get|set|del <file> <dot.path> [json]
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const [cmd, file, path = '', raw] = process.argv.slice(2);
const keys = path.split('.').filter(Boolean);
let data = {};
try { data = JSON.parse(readFileSync(file, 'utf8')); } catch {}
const save = () => {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
};
const last = keys.pop();

if (cmd === 'get') {
  const v = [...keys, last].reduce((o, k) => o?.[k], data);
  if (v !== undefined) console.log(JSON.stringify(v));
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
  console.error('usage: kaito-json.mjs get|set|del <file> <dot.path> [json]');
  process.exit(2);
}
