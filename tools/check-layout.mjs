#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { skillCatalog } from '../helpmekaito/scripts/kaito-catalog.mjs';

try {
  const root = process.argv[2] ?? fileURLToPath(new URL('../', import.meta.url));
  const allow = JSON.parse(readFileSync(new URL('./layout-allowlist.json', import.meta.url), 'utf8'));
  const { skills, bundles } = skillCatalog(root);
  const flat = [...skills.values()].filter((path) => !path.includes('/'));
  const groups = new Map();
  for (const name of [...flat, ...bundles].sort()) {
    const parts = name.split('-');
    for (let i = 1; i <= parts.length; i++) {
      const prefix = parts.slice(0, i).join('-');
      if (!groups.has(prefix)) groups.set(prefix, []);
      groups.get(prefix).push(name);
    }
  }

  for (const [prefix, names] of groups) {
    if (names.length < 2 || !names.some((name) => !bundles.has(name))) continue;
    const exception = Object.hasOwn(allow, prefix) ? allow[prefix] : undefined;
    if (exception?.reason?.trim() && JSON.stringify(names) === JSON.stringify(exception.folders)) continue;
    console.error(`split family ${prefix}: ${names.join(', ')}`);
    process.exitCode = 1;
  }
  if (!process.exitCode) console.log('layout ok');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
