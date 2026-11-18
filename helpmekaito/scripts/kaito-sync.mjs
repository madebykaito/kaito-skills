// Portable stand-ins for rsync and ln -s, so setup runs where neither exists (Git Bash, Alpine).
//   node kaito-sync.mjs mirror [-x PAT]... [-i PAT]... SRC DEST   make DEST's contents match SRC
//   node kaito-sync.mjs into   [-x PAT]... [-i PAT]... DIR SRC... mirror each SRC into DIR/<name>
//   node kaito-sync.mjs link TARGET PATH                          a symlink (a junction on Windows)
// PAT is a name matched anywhere, or a ./path (or /path) from the SRC root. Use ./ in Git Bash,
// which rewrites a /path argument into a Windows path. Excluded entries are neither
// copied nor deleted in DEST, the way rsync --exclude works without --delete-excluded. -i wins over -x.
import { lstatSync, readdirSync, mkdirSync, copyFileSync, rmSync, symlinkSync, readlinkSync, utimesSync, chmodSync } from 'node:fs';
import { join, basename } from 'node:path';

const args = process.argv.slice(2);
const cmd = args.shift();
const ex = [], inc = [];
while (args[0] === '-x' || args[0] === '-i') { const f = args.shift(); (f === '-x' ? ex : inc).push(args.shift()); }
const die = (m) => { console.error(`kaito-sync: ${m}`); process.exit(1); };
const win = process.platform === 'win32';

const anchor = (p) => (p.startsWith('./') ? p.slice(1) : p).replace(/\/$/, '');
const hit = (pats, name, rel) => pats.some((p) => { const a = anchor(p); return a.startsWith('/') ? a === rel : p === name; });
const skip = (name, rel) => !hit(inc, name, rel) && hit(ex, name, rel);
const stat = (p) => { try { return lstatSync(p); } catch { return null; } };

function link(target, path) {
  symlinkSync(target, path, win ? 'junction' : undefined);  // junctions need no admin or Developer Mode
}

// Delete a DEST-only entry, but keep excluded paths inside it (and the folders above them).
function prune(p, rel) {
  if (skip(basename(p), rel)) return;
  const s = stat(p);
  if (s && s.isDirectory() && !s.isSymbolicLink()) {
    for (const n of readdirSync(p)) prune(join(p, n), `${rel}/${n}`);
    if (readdirSync(p).length) return;
  }
  rmSync(p, { recursive: true, force: true });
}

function mirror(src, dst, rel) {
  const s = stat(src);
  if (!s) die(`missing ${src}`);
  const d = stat(dst);
  if (s.isSymbolicLink()) {
    const t = readlinkSync(src);
    if (d && d.isSymbolicLink() && readlinkSync(dst) === t) return;
    if (d) rmSync(dst, { recursive: true, force: true });
    try { symlinkSync(t, dst); } catch { /* shortcut: Windows without Developer Mode cannot copy a file symlink; skip it */ }
    return;
  }
  if (s.isDirectory()) {
    if (d && !d.isDirectory()) rmSync(dst, { recursive: true, force: true });
    if (!d || !d.isDirectory()) mkdirSync(dst, { recursive: true });
    const names = readdirSync(src);
    for (const n of names) {
      const r = `${rel}/${n}`;
      if (!skip(n, r)) mirror(join(src, n), join(dst, n), r);
    }
    const keep = new Set(names);
    for (const n of readdirSync(dst)) {
      if (!keep.has(n)) prune(join(dst, n), `${rel}/${n}`);
    }
    return;
  }
  // A file: copy only when size or mtime differ, as rsync -a does.
  if (d && d.isFile() && d.size === s.size && Math.trunc(d.mtimeMs) === Math.trunc(s.mtimeMs)) return;
  if (d) rmSync(dst, { recursive: true, force: true });
  copyFileSync(src, dst);
  try { chmodSync(dst, s.mode & 0o777); } catch {}  // Windows keeps only the read-only bit
  utimesSync(dst, s.atime, s.mtime);
}

if (cmd === 'mirror' && args.length === 2) mirror(args[0], args[1], '');
else if (cmd === 'into' && args.length >= 1) {
  const dir = args.shift();
  mkdirSync(dir, { recursive: true });
  for (const s of args) mirror(s.replace(/[\\/]+$/, ''), join(dir, basename(s.replace(/[\\/]+$/, ''))), '');
} else if (cmd === 'link' && args.length === 2) link(args[0], args[1]);
else die('usage: mirror|into [-x PAT] [-i PAT] SRC... DEST | link TARGET PATH');
