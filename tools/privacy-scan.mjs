#!/usr/bin/env node
// Scans for private data before it reaches the public repo. Node 22, standard library only.
//   node tools/privacy-scan.mjs [folder] [--no-denylist] [--denylist <file>]
// No folder: scans the files git tracks in this repo. A folder: scans every file under it.
// Two sources of patterns:
//   1. generic patterns below (emails, phones, key shapes, GSTIN, PAN, media metadata);
//   2. a private denylist, one term per line, case-insensitive, never committed:
//      ~/.kaito/privacy-denylist.txt, or the path in KAITO_PRIVACY_DENYLIST.
// Output: path:line: rule: <masked match>. Exit 1 on any hit, 0 and "privacy ok" when clean.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import zlib from 'node:zlib';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.dirname(here);

// ---- arguments
let folder = null, denyPath = null, useDeny = true;
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--no-denylist') useDeny = false;
  else if (a === '--denylist') denyPath = argv[++i];
  else if (a === '-h' || a === '--help') { console.log('usage: privacy-scan.mjs [folder] [--no-denylist] [--denylist <file>]'); process.exit(0); }
  else if (a.startsWith('-')) { console.error(`unknown option: ${a}`); process.exit(2); }
  else if (folder === null) folder = a;
  else { console.error('only one folder allowed'); process.exit(2); }
}
if (folder !== null && !fs.existsSync(folder)) { console.error(`not found: ${folder}`); process.exit(2); }

// ---- allow list (exact matches, case-insensitive)
const allow = new Set(['19abcde1234f1z5', 'abcde1234f', 'kaito@madebykaito.com']);
try {
  for (const l of fs.readFileSync(path.join(here, 'privacy-allow.txt'), 'utf8').split('\n')) {
    const t = l.trim();
    if (t && !t.startsWith('#')) allow.add(t.toLowerCase());
  }
} catch {}
const allowed = (s) => allow.has(s.toLowerCase());
// Lines like "secret@gstack/" allow a rule family inside a path prefix (vendored upstream files).
const scoped = [];
for (const a of allow) { const m = a.match(/^([a-z-]+)@([\w.\/-]*\/[\w.\/-]*)$/); if (m) scoped.push([m[1], m[2]]); }
const scopedOk = (file, rule) => scoped.some(([r, p]) => rule.startsWith(r) && (p.endsWith('/') ? file.startsWith(p) : file === p));

// ---- denylist
let deny = [];
if (useDeny) {
  const p = denyPath || process.env.KAITO_PRIVACY_DENYLIST ||
    path.join(process.env.KAITO_HOME || path.join(os.homedir(), '.kaito'), 'privacy-denylist.txt');
  try {
    deny = fs.readFileSync(p, 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#')).map((l) => l.toLowerCase());
  } catch (e) { if (denyPath || process.env.KAITO_PRIVACY_DENYLIST || e.code !== 'ENOENT') { console.error(`cannot read denylist: ${p}`); process.exit(2); } }
}

// ---- helpers
const mask = (s) => { s = String(s).replace(/\s+/g, ' ').trim(); return s.slice(0, 3) + '***'; };
const hits = [];
const hit = (file, line, rule, match) => !scopedOk(file, rule) && hits.push(`${rule === 'denylist-path' ? mask(file) : file}:${line}: ${rule}: ${mask(match)}`);

const IMG_EXT = /^(png|jpe?g|gif|webp|svg|ico|bmp|tiff?|heic|avif)$/i;
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/g;
const PHONE = [
  /(?<![\w.])(?:\+|00)91[\s-]?[6-9]\d{4}[\s-]?\d{5}(?!\d)/g,
  /(?<![\w.\/-])(?:\+|00)91[\s-]?\d{2}[\s-]?\d{4}[\s-]?\d{4}(?!\d)/g,
  /(?<![\w.\/-])[6-9]\d{4}[\s-]\d{5}(?![\w-])/g,
  /(?<![\w.\/#-])0?[6-9]\d{9}(?![\w.-])/g,
];
const KEYS = [
  ['key-openai', /\bsk-(?:ant-|proj-)?[A-Za-z0-9_-]{20,}/g],
  ['key-github', /\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})/g],
  ['key-slack', /\bxox[abprs]-[A-Za-z0-9-]{10,}/g],
  ['key-aws', /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/g],
  ['key-linear', /\blin_(?:api|oauth)_[A-Za-z0-9]{20,}/g],
  ['key-google', /\bAIza[0-9A-Za-z_-]{35}\b/g],
];
const SECRET_WORD = /\b[\w.-]*(?:key|token|secret|passw(?:or)?d|pwd|credential)[\w.-]*["']?\s*[:=]\s*["']?([A-Za-z0-9+\/_=-]{32,})["']?/gi;
const GSTIN = /\b\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]\b/g;
const PAN = /\b[A-Z]{5}\d{4}[A-Z]\b/g;

function looksSecret(v) {
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v)) return true; // uuid
  if (/(.)\1{7,}/.test(v)) return false;                    // xxxxxxxx, 00000000
  if (/example|your|placeholder|changeme|redacted|dummy|sample|fake/i.test(v)) return false;
  if (/^[a-z]+$/i.test(v) || /^\d+$/.test(v)) return false;  // plain words or numbers
  if (/^[A-Za-z]+(?:[-_][A-Za-z]+)+$/.test(v)) return false; // kebab or snake words
  if (/^[a-z0-9]+(?:-[a-z0-9]+){2,}$/.test(v)) return false;  // slugs
  if (/^[\w-]+(?:\/[\w.-]+)+$/.test(v) && /\//.test(v) && !/[+=]/.test(v) && /^[a-z0-9_\/.-]+$/i.test(v) && v.split('/').every((p) => /^[a-z][\w.-]*$/i.test(p))) return false; // paths
  return /\d/.test(v) && /[A-Za-z]/.test(v);
}

function scanText(file, text) {
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i], n = i + 1;
    for (const m of line.matchAll(EMAIL)) {
      const e = m[0], ext = e.slice(e.lastIndexOf('.') + 1);
      if (IMG_EXT.test(ext) || /@\d+x\.\w+$/.test(e)) continue;
      if (allowed(e) || /@example\.(?:com|org)$/i.test(e) || /^noreply@|@users\.noreply\.github\.com$/i.test(e)) continue;
      hit(file, n, 'email', e);
    }
    for (const re of PHONE) for (const m of line.matchAll(re)) if (!allowed(m[0])) hit(file, n, 'phone', m[0]);
    for (const [rule, re] of KEYS) for (const m of line.matchAll(re)) if (!allowed(m[0]) && !/example|your|xxxx|placeholder|fake|dummy/i.test(m[0])) hit(file, n, rule, m[0]);
    for (const m of line.matchAll(SECRET_WORD)) if (looksSecret(m[1]) && !allowed(m[1])) hit(file, n, 'secret', m[1]);
    for (const m of line.matchAll(GSTIN)) if (!allowed(m[0])) hit(file, n, 'gstin', m[0]);
    for (const m of line.matchAll(PAN)) if (!allowed(m[0]) && !/[A-Z]{5}\d{4}[A-Z]\d/.test(line.slice(Math.max(0, m.index - 2), m.index + 11))) hit(file, n, 'pan', m[0]);
    if (deny.length) {
      const low = line.toLowerCase();
      for (const t of deny) if (low.includes(t)) hit(file, n, 'denylist', t);
    }
  }
}

// ---- media metadata
const u16 = (b, o, le) => (le ? b.readUInt16LE(o) : b.readUInt16BE(o));
const u32 = (b, o, le) => (le ? b.readUInt32LE(o) : b.readUInt32BE(o));
const TAG_NAMES = { 0x013b: 'exif-artist', 0x8298: 'exif-copyright', 0x9c9d: 'exif-author', 0xa431: 'exif-body-serial', 0xa435: 'exif-lens-serial', 0xc62f: 'exif-camera-serial', 0xa430: 'exif-owner', 0x010d: 'exif-document-name', 0x013c: 'exif-host-computer' };

function scanExif(file, buf, off = 0) {
  // buf[off..] is a TIFF header. Reports GPS entries and identifying tags, never values.
  if (buf.length < off + 8) return;
  const le = buf.toString('latin1', off, off + 2) === 'II';
  if (!le && buf.toString('latin1', off, off + 2) !== 'MM') return;
  const seen = new Set();
  const walkIfd = (rel, kind) => {
    if (rel < 8 || seen.has(rel + kind)) return;
    seen.add(rel + kind);
    const o = off + rel;
    if (o + 2 > buf.length) return;
    const count = u16(buf, o, le);
    for (let i = 0; i < count && o + 2 + (i + 1) * 12 <= buf.length; i++) {
      const e = o + 2 + i * 12, tag = u16(buf, e, le);
      if (kind === 'gps') { if (tag >= 1) hit(file, 0, 'media-gps', 'gps tag ' + tag); continue; }
      if (tag === 0x8825) { const p = u32(buf, e + 8, le); const co = off + p; if (p && co + 2 <= buf.length && u16(buf, co, le) > 0) hit(file, 0, 'media-gps', 'gps ifd'); }
      else if (tag === 0x8769) walkIfd(u32(buf, e + 8, le), 'exif');
      else if (TAG_NAMES[tag]) {
        const type = u16(buf, e + 2, le), cnt = u32(buf, e + 4, le);
        const size = (type === 3 ? 2 : 1) * cnt;
        let val;
        if (size > 4) { const p = off + u32(buf, e + 8, le); val = p + size <= buf.length ? buf.subarray(p, p + size) : Buffer.alloc(0); }
        else val = buf.subarray(e + 8, e + 8 + size);
        const s = (tag === 0x9c9d ? val.toString('utf16le') : val.toString('latin1')).replace(/[\0\s]+/g, ' ').trim();
        if (s) hit(file, 0, 'media-' + TAG_NAMES[tag], s);
      }
    }
    const next = (kind === 'ifd0' && o + 6 + count * 12 <= buf.length) ? u32(buf, o + 2 + count * 12, le) : 0;
    if (next) walkIfd(next, 'ifd1');
  };
  walkIfd(u32(buf, off + 4, le), 'ifd0');
}

const XMP_FLAGS = [
  ['media-xmp-author', /(?:dc:creator|tiff:Artist|photoshop:Credit|xmpRights:Owner|photoshop:AuthorsPosition)(?:\s*=\s*"([^"]+)"|\b[^>]*>(?:\s*<[^>]+>)*\s*([^<\s][^<]*))/i],
  ['media-xmp-gps', /(?:exif:GPS(?:Latitude|Longitude)|GPS(?:Latitude|Longitude))\b[^>"=]*[=>]\s*"?([^"<\s][^"<]*)/i],
  ['media-xmp-serial', /(?:aux:SerialNumber|exif:BodySerialNumber|aux:LensSerialNumber)\b[^>"=]*[=>]\s*"?([^"<\s][^"<]*)/i],
];
function scanXmp(file, text) { for (const [rule, re] of XMP_FLAGS) { const m = text.match(re); if (m) hit(file, 0, rule, m[1] || m[2] || m[0]); } }

function scanPng(file, buf) {
  let o = 8;
  while (o + 12 <= buf.length) {
    const len = buf.readUInt32BE(o), type = buf.toString('latin1', o + 4, o + 8), body = buf.subarray(o + 8, o + 8 + len);
    if (type === 'tEXt' || type === 'iTXt' || type === 'zTXt') {
      const z = body.indexOf(0), key = body.toString('latin1', 0, z < 0 ? body.length : z);
      let val = Buffer.alloc(0);
      if (z >= 0) {
        try {
          if (type === 'tEXt') val = body.subarray(z + 1);
          else if (type === 'zTXt') val = zlib.inflateSync(body.subarray(z + 2));
          else { // iTXt: flag, method, language\0, translated key\0, text
            const flag = body[z + 1]; let q = body.indexOf(0, z + 3); q = body.indexOf(0, q + 1);
            val = flag ? zlib.inflateSync(body.subarray(q + 1)) : body.subarray(q + 1);
          }
        } catch {}
      }
      const text = val.toString('utf8');
      if (/^(author|artist|creator|copyright|camera|serial|gps|location|email|owner|source)/i.test(key)) hit(file, 0, 'media-png-' + key.toLowerCase().slice(0, 12), text.replace(/^[\0\s]+/, '') || key);
      if (/^XML:com\.adobe\.xmp$/.test(key)) scanXmp(file, text);
    } else if (type === 'eXIf') scanExif(file, body, 0);
    o += 12 + len;
    if (type === 'IEND') break;
  }
}

function scanJpeg(file, buf) {
  let o = 2;
  while (o + 4 <= buf.length && buf[o] === 0xff) {
    const marker = buf[o + 1];
    if (marker === 0xda || marker === 0xd9) break;
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) { o += 2; continue; }
    const len = buf.readUInt16BE(o + 2), body = buf.subarray(o + 4, o + 2 + len);
    if (marker === 0xe1) {
      if (body.toString('latin1', 0, 6) === 'Exif\0\0') scanExif(file, body, 6);
      else if (body.toString('latin1', 0, 28).startsWith('http://ns.adobe.com/xap/1.0/')) scanXmp(file, body.toString('utf8'));
    } else if (marker === 0xed && body.toString('latin1', 0, 13) === 'Photoshop 3.0') {
      if (/\x1c\x02(?:\x50|\x55|\x73)/.test(body.toString('latin1'))) hit(file, 0, 'media-iptc', 'iptc byline');
    }
    o += 2 + len;
  }
}

function scanWebp(file, buf) {
  let o = 12;
  while (o + 8 <= buf.length) {
    const type = buf.toString('latin1', o, o + 4), len = buf.readUInt32LE(o + 4), body = buf.subarray(o + 8, o + 8 + len);
    if (type === 'EXIF') scanExif(file, body, body.toString('latin1', 0, 6) === 'Exif\0\0' ? 6 : 0);
    else if (type === 'XMP ') scanXmp(file, body.toString('utf8'));
    o += 8 + len + (len & 1);
  }
}

const MP4_FLAG = { '\xa9xyz': 'media-mp4-gps', '\xa9aut': 'media-mp4-author', '\xa9ART': 'media-mp4-author', '\xa9own': 'media-mp4-author', '\xa9cpy': 'media-mp4-copyright', '\xa9mak': 'media-mp4-camera', '\xa9mod': 'media-mp4-camera', '\xa9swr': null, 'loci': 'media-mp4-gps', 'cprt': 'media-mp4-copyright', 'auth': 'media-mp4-author', 'perf': 'media-mp4-author' };
function mp4Walk(file, buf, start, end, depth) {
  let o = start;
  while (o + 8 <= end) {
    let size = buf.readUInt32BE(o); const type = buf.toString('latin1', o + 4, o + 8);
    if (size === 1) { if (o + 16 > end) break; size = Number(buf.readBigUInt64BE(o + 8)); }
    if (size < 8 || o + size > end) break;
    if (MP4_FLAG[type]) hit(file, 0, MP4_FLAG[type], type.replace('\xa9', '(c)'));
    if (type === 'uuid' || type === 'XMP_') scanXmp(file, buf.toString('utf8', o + 8, Math.min(o + size, o + 8 + 200000)));
    if (depth < 5 && (type === 'moov' || type === 'udta' || type === 'ilst' || type === 'trak' || type === 'meta')) {
      let inner = o + 8;
      if (type === 'meta' && inner + 4 <= o + size && buf.readUInt32BE(inner) === 0) inner += 4; // full box header
      mp4Walk(file, buf, inner, o + size, depth + 1);
    }
    if (depth >= 1 && /^\xa9/.test(type) === false && depth > 1 && type === 'data') { /* values are not read */ }
    o += size;
  }
}
function scanMp4(file, abs) {
  const fd = fs.openSync(abs, 'r');
  try {
    const total = fs.fstatSync(fd).size; let o = 0; const head = Buffer.alloc(16);
    while (o + 8 <= total) {
      if (fs.readSync(fd, head, 0, 16, o) < 8) break;
      let size = head.readUInt32BE(0); const type = head.toString('latin1', 4, 8);
      if (size === 1) size = Number(head.readBigUInt64BE(8)); else if (size === 0) size = total - o;
      if (size < 8) break;
      if ((type === 'moov' || type === 'uuid' || type === 'meta' || type === 'udta') && size <= 32 * 1024 * 1024) {
        const b = Buffer.alloc(size); fs.readSync(fd, b, 0, size, o);
        mp4Walk(file, b, 0, size, 0);
        const lat = b.toString('latin1');
        if (/com\.apple\.quicktime\.location|ISO6709/.test(lat)) hit(file, 0, 'media-mp4-gps', 'quicktime location key');
        if (/com\.apple\.quicktime\.(?:author|artist|copyright)/.test(lat)) hit(file, 0, 'media-mp4-author', 'quicktime author key');
      }
      o += size;
    }
  } finally { fs.closeSync(fd); }
}

function scanMedia(file, abs) {
  const ext = path.extname(file).slice(1).toLowerCase();
  let buf;
  if (ext === 'mp4' || ext === 'mov' || ext === 'm4v' || ext === 'm4a') return scanMp4(file, abs);
  if (!/^(png|jpe?g|webp)$/.test(ext)) return;
  buf = fs.readFileSync(abs);
  if (ext === 'png' && buf.toString('latin1', 1, 4) === 'PNG') scanPng(file, buf);
  else if (/^jpe?g$/.test(ext) && buf[0] === 0xff && buf[1] === 0xd8) scanJpeg(file, buf);
  else if (ext === 'webp' && buf.toString('latin1', 0, 4) === 'RIFF') scanWebp(file, buf);
}

// ---- file list
function listFiles() {
  if (folder === null) {
    const out = execFileSync('git', ['ls-files', '-z'], { cwd: repo, maxBuffer: 1 << 28 }).toString('utf8');
    return { root: repo, files: out.split('\0').filter(Boolean) };
  }
  const root = path.resolve(folder), files = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      if (e.name === '.git' || e.name === 'node_modules') continue;
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p); else if (e.isFile()) files.push(path.relative(root, p));
    }
  };
  walk(root);
  return { root, files };
}

const { root, files } = listFiles();
for (const rel of files) {
  const abs = path.join(root, rel);
  let st;
  try { st = fs.statSync(abs); } catch { continue; }  // deleted or a dangling link
  if (!st.isFile()) continue;
  if (deny.length) { const low = rel.toLowerCase(); for (const t of deny) if (low.includes(t)) hit(rel, 0, 'denylist-path', t); }
  try { scanMedia(rel, abs); } catch (e) { console.error(`privacy: cannot parse media ${mask(rel)}: ${e.message}`); }
  if (st.size > 256 * 1024 * 1024) continue;
  const buf = fs.readFileSync(abs);
  if (buf.subarray(0, 8000).includes(0)) continue; // binary: media handled above
  scanText(rel, buf.toString('utf8'));
}

const uniq = [...new Set(hits)];
if (uniq.length) { console.log(uniq.join('\n')); console.error(`privacy: ${uniq.length} hit${uniq.length === 1 ? '' : 's'}`); process.exit(1); }
console.log('privacy ok');
