// Discover installable skills. Each value is a slash-separated path from the catalog root.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const slug = /^[a-z0-9][a-z0-9_-]*$/;
const isText = (value) => typeof value === 'string' && value.trim() !== '';
const hasSkill = (dir) => statSync(join(dir, 'SKILL.md'), { throwIfNoEntry: false })?.isFile();

export function skillCatalog(root) {
  const skills = new Map(), bundles = new Set();
  function add(name, path) {
    if (skills.has(name)) throw new Error(`duplicate skill ${name}: ${skills.get(name)}, ${path}`);
    skills.set(name, path);
  }
  const folders = readdirSync(root, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
  for (const entry of folders) {
    const name = entry.name;
    if (!entry.isDirectory() || name === 'gstack' || name === '_gstack-claude' || name === '_gstack-codex' || name.startsWith('.')) continue;
    const dir = join(root, name);
    const standalone = hasSkill(dir);
    const manifest = join(dir, 'bundle.json');
    if (!existsSync(manifest)) {
      if (standalone) {
        if (!slug.test(name)) throw new Error(`${dir}: invalid skill folder name`);
        add(name, name);
      }
      continue;
    }
    let bundle;
    try { bundle = JSON.parse(readFileSync(manifest, 'utf8')); }
    catch (error) { throw new Error(`${manifest}: ${error.message}`); }
    if (standalone || !slug.test(name) || bundle?.name !== name || !isText(bundle.source) ||
        !isText(bundle.license) || !Array.isArray(bundle.skills) || !bundle.skills.length) {
      throw new Error(`${manifest}: expected matching name, source, license and a nonempty skills list, with no root SKILL.md`);
    }
    const children = new Set();
    for (const skill of bundle.skills) {
      if (typeof skill !== 'string' || !slug.test(skill) || skill === 'gstack' || children.has(skill) ||
          !hasSkill(join(dir, skill))) {
        throw new Error(`${manifest}: invalid, duplicate or missing skill ${JSON.stringify(skill)}`);
      }
      children.add(skill);
      add(skill, `${name}/${skill}`);
    }
    for (const child of readdirSync(dir, { withFileTypes: true })) {
      if (child.isDirectory() && hasSkill(join(dir, child.name)) && !children.has(child.name)) {
        throw new Error(`${manifest}: unlisted skill ${child.name}`);
      }
    }
    bundles.add(name);
  }
  return { skills, bundles };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [root = fileURLToPath(new URL('../../', import.meta.url)), name] = process.argv.slice(2);
  try {
    if (existsSync(root)) {
      const { skills } = skillCatalog(root);
      if (name === undefined) for (const path of skills.values()) console.log(path);
      else if (skills.has(name)) console.log(skills.get(name));
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
