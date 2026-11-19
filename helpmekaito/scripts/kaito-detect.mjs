// First use in a project: which tracker does this repo seem to live in? Read-only, local only, no network.
// node kaito-detect.mjs <repo-path> <memory-dir>
// Prints one line per candidate, strongest first:
//   candidate: <manager> <id> <name> | strength=<strong|weak> | evidence=<what was seen>
// then "known: <managers with a stored structure map>". Prints "candidate: none" when nothing points anywhere.
// It only reports evidence. Mapping a tracker is always the user's yes.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, basename } from 'node:path';
import { execFileSync } from 'node:child_process';

const [repo, mem] = process.argv.slice(2);
const git = (...a) => { try { return execFileSync('git', ['-C', repo, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return ''; } };
const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '');
const one = (s) => String(s ?? '').replace(/[\r\n|]+/g, ' ').trim();

const maps = {};
try {
  for (const f of readdirSync(join(mem, 'managers'))) if (f.endsWith('.json')) {
    try { maps[f.slice(0, -5)] = JSON.parse(readFileSync(join(mem, 'managers', f), 'utf8')); } catch {}
  }
} catch {}

const found = new Map();  // "manager id" -> { manager, id, name, strong, evidence[] }
const hit = (manager, id, name, strong, evidence) => {
  const k = `${manager} ${id}`, c = found.get(k) || { manager, id, name: one(name), strong: false, evidence: [] };
  c.strong ||= strong; c.evidence.push(evidence); found.set(k, c);
};

// 1. Ticket keys in the branch name and recent commit subjects, matched against known project keys only.
const branch = git('rev-parse', '--abbrev-ref', 'HEAD');
const subjects = git('log', '-30', '--format=%s').split('\n').filter(Boolean);
const keysIn = (s) => [...String(s).matchAll(/(?:^|[^A-Za-z0-9])([A-Za-z][A-Za-z0-9]{1,9})-\d+(?![A-Za-z0-9])/g)].map((m) => m[1].toUpperCase());
for (const [id, b] of Object.entries(maps.plane?.boards || {})) {
  const key = String(b.identifier || '').toUpperCase();
  if (!key) continue;
  const inBranch = keysIn(branch).includes(key), n = subjects.filter((s) => keysIn(s).includes(key)).length;
  if (inBranch) hit('plane', id, b.name, true, `branch ${branch} carries the key ${key}`);
  if (n) hit('plane', id, b.name, n >= 2, `${n} of the last ${subjects.length} commits carry the key ${key}`);
}

// 2. Tracker links in the repo's own docs.
const docs = ['README.md', 'CONTRIBUTING.md', 'AGENTS.md', 'CLAUDE.md', '.github/PULL_REQUEST_TEMPLATE.md', '.github/pull_request_template.md', 'docs/README.md'];
for (const d of docs) {
  let text = '';
  try { text = readFileSync(join(repo, d), 'utf8').slice(0, 200000); } catch { continue; }
  for (const m of text.matchAll(/https:\/\/trello\.com\/b\/([A-Za-z0-9]{8})(?:\/([A-Za-z0-9-]+))?/g)) {
    // The link names one board. A stored board is the same one only if its own link says so, never because the name matches.
    const known = Object.entries(maps.trello?.boards || {}).find(([id, b]) => id === m[1] || b.shortLink === m[1] || String(b.url || '').includes(`/b/${m[1]}`));
    hit('trello', known ? known[0] : m[1], known ? known[1].name : m[2] || m[1], true, `${d} links the board`);
  }
  for (const m of text.matchAll(/https:\/\/[A-Za-z0-9.-]+\/[A-Za-z0-9_-]+\/projects\/([0-9a-f]{8}-[0-9a-f-]{27})(?:\/modules\/([0-9a-f]{8}-[0-9a-f-]{27}))?/g)) {
    const b = maps.plane?.boards?.[m[1]];
    if (b) hit('plane', m[2] && b.modules?.some((x) => x.id === m[2]) ? `${m[1]}/${m[2]}` : m[1], b.name, true, `${d} links the project`);
  }
  for (const m of text.matchAll(/https:\/\/([A-Za-z0-9-]+)\.atlassian\.net\/(?:browse\/([A-Z][A-Z0-9]+)-\d+|jira\/software\/(?:c\/)?projects\/([A-Z][A-Z0-9]+))/g)) {
    hit('jira', m[2] || m[3], `${m[2] || m[3]} on ${m[1]}.atlassian.net`, true, `${d} links the Jira project`);
  }
}

// 3. The repo or its remote is named like a known board, project or module. A name alone is weak evidence.
const names = new Set([basename(repo), git('remote', 'get-url', 'origin').replace(/\.git$/, '').split(/[/:]/).pop()].map(norm).filter((n) => n.length >= 3));
for (const [manager, map] of Object.entries(maps)) for (const [id, b] of Object.entries(map.boards || {})) {
  if (names.has(norm(b.name))) hit(manager, id, b.name, false, `the repo is named like the ${manager === 'trello' ? 'board' : 'project'}`);
  for (const mod of b.modules || []) if (names.has(norm(mod.name))) hit(manager, `${id}/${mod.id}`, `${b.name} / ${mod.name}`, false, 'the repo is named like the module');
}

const rows = [...found.values()].sort((a, b) => Number(b.strong) - Number(a.strong));
for (const c of rows) console.log(`candidate: ${c.manager} ${c.id} ${c.name} | strength=${c.strong ? 'strong' : 'weak'} | evidence=${c.evidence.join('; ')}`);
if (!rows.length) console.log('candidate: none');
console.log(`known: ${Object.keys(maps).sort().join(' ') || 'none'}`);
if (existsSync(join(repo, '.git')) && /github\.com/.test(git('remote', 'get-url', 'origin'))) console.log('github: yes');
