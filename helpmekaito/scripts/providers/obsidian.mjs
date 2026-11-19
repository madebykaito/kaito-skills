// Obsidian: one note per task under tasks/<slug>/, no remote. The notes are the source.
import { mkdirSync, readdirSync, existsSync, unlinkSync } from 'node:fs';
import { join, sep } from 'node:path';
import { D, die, one, fm, slug, inside, atomic, rnd, openItems, taskFiles, writeIndex, locked, itemId, opts } from './lib.mjs';

const STATUS = ['todo', 'doing', 'done'];
function op(op, a) {
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

export default {
  remote: false,
  indexDone: false,  // done notes move to archive/ and leave the index
  isDone: (t) => t.meta.status === 'done',
  where: (t) => t.meta.status,
  commands: {},
  op,
};
