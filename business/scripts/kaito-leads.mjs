#!/usr/bin/env node
import fs from 'node:fs';
import { EXIT, fail, run, parseArgs, only, openDb, tx, checkOwnerId, readOwner, ownerTz, parseWhen, isoUtc } from './kaito-ledger-lib.mjs';

const usage = 'usage: kaito-leads.mjs import <csv> --owner <id> | list --owner <id> | move <id> --owner <id> --stage <qualify|outreach|review|retro> --note <text> | touch <id> --owner <id> --note <text> [--due <date>] | callbacks --owner <id>';
function csv(text) {
  const rows = []; let row = [], field = '', quoted = false, after = false;
  text = text.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) { if (c === '"' && text[i+1] === '"') { field += '"'; i++; } else if (c === '"') { quoted = false; after = true; } else field += c; }
    else if (c === '"' && !field && !after) quoted = true;
    else if (c === ',' || c === '\n') { row.push(field); field = ''; after = false; if (c === '\n') { rows.push(row); row = []; } }
    else if (c === '"' || after) fail(EXIT.usage, 'malformed CSV');
    else field += c;
  }
  if (quoted) fail(EXIT.usage, 'unclosed CSV quote');
  if (field || row.length || after) { row.push(field); rows.push(row); }
  return rows;
}
function main(argv) {
  const a = parseArgs(argv, {bool:['json']}); const [cmd, arg] = a._;
  if (!cmd || cmd === 'help' || argv.includes('--help')) { console.log(usage); return cmd ? 0 : 2; }
  only(a, ['owner','stage','note','due','json']);
  const owner = checkOwnerId(a.owner); if (!readOwner(owner)) fail(EXIT.notFound, `owner not found: ${owner}`);
  const db = openDb(), now = isoUtc(Date.now());
  if (cmd === 'import') {
    if (!arg || a._.length !== 2) fail(EXIT.usage, usage);
    let rows; try { rows = csv(fs.readFileSync(arg, 'utf8')); } catch (e) { if (e.code === 'ENOENT') fail(EXIT.notFound, `file not found: ${arg}`); throw e; }
    const header = rows.shift()?.map(x => x.trim().toLowerCase());
    if (!header || new Set(header).size !== header.length || !header.includes('name') || !header.includes('email') || header.some(x => !['name','email','company'].includes(x))) fail(EXIT.usage, 'CSV headers must contain name,email and optional company');
    const good = [], bad = [];
    rows.forEach((r,i) => { const v = Object.fromEntries(header.map((h,j) => [h,(r[j] ?? '').trim()])); if (r.length !== header.length || !v.name || /[\r\n\t]/.test(v.name + (v.company || '')) || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v.email)) bad.push(i+2); else good.push(v); });
    let added = 0, duplicates = 0;
    tx(db, () => { for (const v of good) { const r = db.prepare('INSERT OR IGNORE INTO leads(owner,name,email,company,created_at) VALUES(?,?,?,?,?)').run(owner,v.name,v.email.toLowerCase(),v.company || '',now); if (r.changes) { added++; db.prepare('INSERT INTO lead_stages(lead_id,stage,note,at) VALUES(?,?,?,?)').run(r.lastInsertRowid,'qualify','Imported',now); } else duplicates++; } });
    console.log(`imported=${added}\nduplicates=${duplicates}\nbad_rows=${bad.join(',')}`); return bad.length ? 1 : 0;
  }
  if (cmd === 'list' || cmd === 'callbacks') {
    if (arg) fail(EXIT.usage, usage);
    const rows = cmd === 'list' ? db.prepare('SELECT * FROM leads WHERE owner=? ORDER BY id').all(owner) : db.prepare("SELECT l.id AS lead_id,l.name,q.id AS queue_id,q.due_date,q.due_at,q.title FROM leads l JOIN lead_touches t ON t.lead_id=l.id JOIN queue_items q ON q.id=t.queue_id WHERE l.owner=? AND q.state='open' ORDER BY coalesce(q.due_date,q.due_at),q.id").all(owner);
    if (cmd === 'list') for (const row of rows) { row.history = db.prepare('SELECT stage,note,at FROM lead_stages WHERE lead_id=? ORDER BY id').all(row.id); row.touches = db.prepare('SELECT note,at,queue_id FROM lead_touches WHERE lead_id=? ORDER BY id').all(row.id); }
    if (a.json) console.log(JSON.stringify(rows)); else for (const row of rows) console.log(JSON.stringify(row)); return 0;
  }
  const id = Number(arg); if (!Number.isSafeInteger(id) || id < 1 || a._.length !== 2) fail(EXIT.usage, usage);
  const lead = db.prepare('SELECT * FROM leads WHERE id=? AND owner=?').get(id,owner); if (!lead) fail(EXIT.notFound, 'lead not found');
  if (!a.note || !a.note.trim()) fail(EXIT.usage, '--note is required');
  if (cmd === 'move') {
    if (!['qualify','outreach','review','retro'].includes(a.stage)) fail(EXIT.usage, usage);
    tx(db, () => { db.prepare('UPDATE leads SET stage=? WHERE id=?').run(a.stage,id); db.prepare('INSERT INTO lead_stages(lead_id,stage,note,at) VALUES(?,?,?,?)').run(id,a.stage,a.note,now); }); console.log(`id=${id}\nstage=${a.stage}`); return 0;
  }
  if (cmd === 'touch') {
    let w = a.due ? parseWhen(a.due, ownerTz(owner)) : null;
    tx(db, () => { let q = null; if (w) q = db.prepare('INSERT INTO queue_items(owner,kind,title,due_at,due_date,all_day,created_at) VALUES(?,?,?,?,?,?,?)').run(owner,'callback',`Follow up: ${lead.name}`,w.allDay ? null : isoUtc(w.ms),w.allDay ? w.date : null,w.allDay ? 1 : 0,now).lastInsertRowid; db.prepare('INSERT INTO lead_touches(lead_id,note,at,queue_id) VALUES(?,?,?,?)').run(id,a.note,now,q); if (q) console.log(`queue_id=${q}`); }); return 0;
  }
  fail(EXIT.usage, usage);
}
await run(main);
