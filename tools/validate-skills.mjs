#!/usr/bin/env node
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { skillCatalog } from '../helpmekaito/scripts/kaito-catalog.mjs';

const ignored = new Set(['.git', '.codegraph', 'node_modules', 'dist']);
let checked = 0;
let failures = 0;

function validate(file) {
  checked++;
  const frontmatter = /^---\r?\n([\s\S]*?)^---[ \t]*(?:\r?\n|$)/m.exec(readFileSync(file, 'utf8'));
  const fields = frontmatter?.index === 0 ? frontmatter[1] : '';
  const names = [...fields.matchAll(/^name:[ \t]*(.*?)\s*$/gm)];
  const name = names[0]?.[1].replace(/^(['"])(.*)\1$/, '$2');
  const descriptions = [...fields.matchAll(/^description:[ \t]*([^\r\n]*)(?:\r?\n((?:[ \t]+[^\r\n]*\r?\n)*))?/gm)];
  const scalar = descriptions[0]?.[1].trim();
  const description = /^[>|][+-]?$/.test(scalar) ? descriptions[0]?.[2]?.trim() : scalar;
  if (names.length !== 1 || descriptions.length !== 1 || name !== path.basename(path.dirname(file)) ||
      !description || /^(?:null|~|""|'')$/i.test(description)) {
    console.error(`${file}: expected a single name matching its folder and a nonempty description`);
    failures++;
  }
}

function walk(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory() && !ignored.has(entry.name)) walk(file);
    else if (entry.isFile() && entry.name === 'SKILL.md') validate(file);
  }
}
const root = process.argv[2] ?? '.';
try {
  skillCatalog(root);
  walk(root);
} catch (error) {
  console.error(error.message);
  failures++;
}
if (failures || !checked) process.exitCode = 1;
else console.log(`skills ok (${checked})`);
