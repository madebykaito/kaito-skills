import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { EXIT, fail, parseWhen } from './kaito-ledger-lib.mjs';

const GSTIN = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
const STATES = {
  '01': 'Jammu and Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh',
  '05': 'Uttarakhand', '06': 'Haryana', '07': 'Delhi', '08': 'Rajasthan', '09': 'Uttar Pradesh',
  10: 'Bihar', 11: 'Sikkim', 12: 'Arunachal Pradesh', 13: 'Nagaland', 14: 'Manipur', 15: 'Mizoram',
  16: 'Tripura', 17: 'Meghalaya', 18: 'Assam', 19: 'West Bengal', 20: 'Jharkhand', 21: 'Odisha',
  22: 'Chhattisgarh', 23: 'Madhya Pradesh', 24: 'Gujarat', 26: 'Dadra and Nagar Haveli and Daman and Diu',
  27: 'Maharashtra', 29: 'Karnataka', 30: 'Goa', 31: 'Lakshadweep', 32: 'Kerala', 33: 'Tamil Nadu',
  34: 'Puducherry', 35: 'Andaman and Nicobar Islands', 36: 'Telangana', 37: 'Andhra Pradesh', 38: 'Ladakh',
};
export const ACTIONS = { invoice: 'invoice.issue', quote: 'quote.issue', credit: 'credit-note.issue' };
export const TITLES = { invoice: 'Invoice', quote: 'Quote', credit: 'Credit note' };

export function jsonFile(file) {
  if (!file) fail(EXIT.usage, 'a JSON input file is required');
  let data;
  try { data = fs.readFileSync(file, 'utf8'); }
  catch (error) {
    if (error.code === 'ENOENT') fail(EXIT.notFound, `file not found: ${file}`);
    throw error;
  }
  let value;
  try { value = JSON.parse(data); } catch { fail(EXIT.usage, 'invalid JSON input'); }
  return object(value, 'JSON input');
}

function object(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(EXIT.usage, `${label} must be an object`);
  return value;
}

export function text(value, label, max = 500) {
  if (typeof value !== 'string' || !value.trim() || value.length > max ||
      /[\u0000-\u001f\u007f-\u009f\u061c\u200e\u200f\u2028-\u202e\u2066-\u2069\ufeff\ufff9-\ufffb]/u.test(value)) {
    fail(EXIT.usage, `${label} must be one line of 1–${max} characters`);
  }
  return value.trim();
}

export function day(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) fail(EXIT.usage, 'date must be YYYY-MM-DD');
  return parseWhen(value, 'UTC').date;
}

function stateCode(value, label) {
  if (typeof value !== 'string' || !Object.hasOwn(STATES, value)) fail(EXIT.usage, `${label} needs an Indian GST state code`);
  return value;
}

function party(value) {
  const gstin = value.gstin || null;
  if (gstin !== null && (typeof gstin !== 'string' || !GSTIN.test(gstin))) fail(EXIT.usage, 'invalid GSTIN format');
  return { name: text(value.name, 'name'), address: text(value.address, 'address'), gstin };
}

function buyer(value) {
  object(value, 'client');
  const country = value.country ?? 'IN';
  if (typeof country !== 'string' || !/^[A-Z]{2}$/.test(country)) fail(EXIT.usage, 'client country needs a two-letter country code');
  const client = party(value);
  const state = country === 'IN' ? stateCode(value.state_code, 'client') : null;
  if (client.gstin && client.gstin.slice(0, 2) !== state) fail(EXIT.usage, 'client GSTIN state differs from place of supply');
  if (country !== 'IN' && value.state_code) fail(EXIT.usage, 'omit the Indian state code for exports');
  const email = value.email === undefined ? null : text(value.email, 'client email', 254);
  if (email && !/^[^\s@,;<>"]+@[^\s@,;<>"]+\.[^\s@,;<>"]+$/.test(email)) fail(EXIT.usage, 'client email must be a single address');
  return { ...client, country, state_code: state, email };
}

function taxMode(issuer, client, config) {
  if (!issuer.gstin) {
    if (client.country !== 'IN') fail(EXIT.human, 'registered supplier details are required for this export workflow');
    return 'unregistered';
  }
  const origin = stateCode(issuer.gstin.slice(0, 2), 'issuer');
  if (client.country !== 'IN') {
    if (!['lut', 'igst-paid'].includes(config.export_mode)) fail(EXIT.human, 'set export_mode to lut or igst-paid in money.json');
    return config.export_mode;
  }
  if (client.state_code !== origin) return 'inter';
  return ['04', '26', '31', '35', '38'].includes(origin) ? 'union' : 'intra';
}

function paise(integer) {
  if (integer > BigInt(Number.MAX_SAFE_INTEGER)) fail(EXIT.usage, 'amount exceeds the safe paise range');
  return Number(integer);
}

// Non-negative exact rationals. Round ties up at each line and once per component.
function rounded(numerator, denominator) {
  return paise((2n * numerator + denominator) / (2n * denominator));
}

function line(value, mode) {
  object(value, 'line');
  const { quantity, unit_paise: price, hsn_sac: code, gst_bps: rate } = value;
  if (typeof quantity !== 'string' || !/^\d{1,9}(\.\d{1,6})?$/.test(quantity) || !/[1-9]/.test(quantity)) {
    fail(EXIT.usage, 'quantity needs a positive decimal string with up to six fractional digits');
  }
  if (!Number.isSafeInteger(price) || price < 0) fail(EXIT.usage, 'unit_paise needs a non-negative integer');
  if (mode !== 'unregistered' || code !== undefined) {
    if (typeof code !== 'string' || !/^(\d{4}|\d{6}|\d{8})$/.test(code)) fail(EXIT.usage, 'hsn_sac needs 4, 6 or 8 digits');
  }
  if (mode !== 'unregistered' && (!Number.isSafeInteger(rate) || rate < 0 || rate > 10000)) {
    fail(EXIT.usage, 'gst_bps needs the GST rate in integer basis points');
  }
  const [whole, fraction = ''] = quantity.split('.');
  const net = rounded(BigInt(price) * BigInt(whole + fraction), 10n ** BigInt(fraction.length));
  const nominalRate = ['unregistered', 'lut'].includes(mode) ? 0 : rate;
  const tax = BigInt(net) * BigInt(nominalRate);
  const half = ['intra', 'union'].includes(mode) ? rounded(tax, 20000n) : 0;
  const igst = ['inter', 'igst-paid'].includes(mode) ? rounded(tax, 10000n) : 0;
  const total = paise(BigInt(net) + BigInt(half) * 2n + BigInt(igst));
  return {
    description: text(value.description, 'description'), quantity, unit: text(value.unit, 'unit', 40),
    unit_paise: price, hsn_sac: code ?? null, gst_bps: nominalRate, net, cgst: half,
    sgst: mode === 'intra' ? half : 0, utgst: mode === 'union' ? half : 0, igst, total,
  };
}

export function documentPayload(input, owner, config, kind) {
  if ((owner.currency ?? 'INR') !== 'INR') fail(EXIT.human, 'Money requires INR');
  const issuer = party({ ...owner, address: config.address });
  const client = buyer(input.client);
  const mode = taxMode(issuer, client, config);
  if (!Array.isArray(input.lines) || !input.lines.length || input.lines.length > 250) fail(EXIT.usage, 'provide 1–250 lines');
  const lines = input.lines.map((value) => line(value, mode));
  const totals = {};
  for (const field of ['net', 'cgst', 'sgst', 'utgst', 'igst', 'total']) {
    totals[field] = paise(lines.reduce((sum, row) => sum + BigInt(row[field]), 0n));
  }
  if (!totals.total) fail(EXIT.usage, 'document total must be positive');
  return {
    issuer, client, mode, lines, totals, place_of_supply: client.state_code ? STATES[client.state_code] : client.country,
    due_date: kind === 'invoice' ? day(input.due_date) : null,
    terms: input.terms === undefined ? null : text(input.terms, 'terms', 1000),
  };
}

const INLINE = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
const escape = (value) => String(value).replace(/[&<>"']/g, (char) => INLINE[char]);

export function inr(value) {
  const integer = BigInt(value);
  return `INR ${integer / 100n}.${String(integer % 100n).padStart(2, '0')}`;
}

function rateLabel(bps) {
  const thousandths = bps * 10;
  return `${Math.floor(thousandths / 1000)}.${String(thousandths % 1000).padStart(3, '0').replace(/0+$/, '').padEnd(1, '0')}%`;
}

export function renderHtml(doc, issue) {
  const { issuer, client, mode, place_of_supply: place, due_date: due, lines, totals, terms, credit } = doc.payload;
  const title = doc.kind === 'invoice' && issuer.gstin ? 'Tax invoice' : TITLES[doc.kind];
  const heading = issue ? title : `Draft ${title.toLowerCase()}`;
  const taxes = { intra: ['cgst', 'sgst'], union: ['cgst', 'utgst'], inter: ['igst'], lut: ['igst'], 'igst-paid': ['igst'], unregistered: [] }[mode];
  const partyHtml = (p) => `<strong>${escape(p.name)}</strong><br>${escape(p.address)}${p.country ? `<br>${escape(p.country)}` : ''}${p.gstin ? `<br>GSTIN ${escape(p.gstin)}` : ''}`;
  const places = client.state_code ? `${client.state_code} ${place}` : place;
  const endorsement = mode === 'lut'
    ? 'Supply meant for export under letter of undertaking without payment of IGST'
    : mode === 'igst-paid' ? 'Supply meant for export on payment of IGST' : '';
  const taxCell = (row, tax) => mode === 'lut'
    ? 'Nil'
    : `${inr(row[tax])} (${rateLabel(taxes.length === 2 ? row.gst_bps / 2 : row.gst_bps)})`;
  const rows = lines.map((row) => `<tr><td>${escape(row.description)}</td><td>${escape(row.hsn_sac ?? '–')}</td><td>${escape(row.quantity)} ${escape(row.unit)}</td><td class="num">${inr(row.unit_paise)}</td><td class="num">${inr(row.net)}</td>${taxes.map((tax) => `<td class="num">${taxCell(row, tax)}</td>`).join('')}</tr>`).join('\n');
  return `<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<title>${escape(heading)}${issue ? ` ${escape(issue.number)}` : ''}</title>
<style>
@page { size: A4; margin: 16mm 12mm; }
body { font: 14px/1.45 system-ui, sans-serif; color: #151a1e; max-width: 900px; margin: 2rem auto; padding: 0 12px; overflow-wrap: anywhere; }
h1 { font-size: 30px; margin: 0; } h2 { font-size: 14px; margin-bottom: .4em; }
.parties { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; margin: 24px 0; }
table { width: 100%; border-collapse: collapse; margin: 20px 0; } tr { break-inside: avoid; }
th, td { text-align: left; padding: 8px 5px; border-bottom: 1px solid #c8cfd4; vertical-align: top; }
.num { text-align: right; } .totals { width: auto; max-width: 100%; margin-left: auto; }
@media print { body { margin: 0; padding: 0; font-size: 11px; } }
</style>
<h1>${escape(heading)}</h1>
${issue ? `<p><strong>${escape(issue.number)}</strong><br>Issued ${escape(issue.date)}</p>` : ''}
<div class="parties"><section><h2>From</h2>${partyHtml(issuer)}</section><section><h2>Bill to</h2>${partyHtml(client)}</section></div>
<p>Place of supply ${escape(places)}${due ? `<br>Payment due ${escape(due)}` : ''}</p>
${endorsement ? `<p><strong>${endorsement}</strong></p>` : ''}
${credit ? `<p>Credits ${escape(credit.number)} issued ${escape(credit.date)}<br>Reason ${escape(credit.reason)}</p>` : ''}
<table><thead><tr><th>Description</th><th>HSN/SAC</th><th>Quantity</th><th class="num">Unit price</th><th class="num">Taxable value</th>${taxes.map((tax) => `<th class="num">${tax.toUpperCase()}</th>`).join('')}</tr></thead><tbody>
${rows}
</tbody></table>
<table class="totals"><tbody><tr><th>Subtotal</th><td class="num">${inr(totals.net)}</td></tr>${taxes.map((tax) => `<tr><th>${tax.toUpperCase()}</th><td class="num">${mode === 'lut' ? 'Nil' : inr(totals[tax])}</td></tr>`).join('')}
<tr><th>${credit ? 'Total credited' : 'Total'}</th><td class="num"><strong>${inr(totals.total)}</strong></td></tr></tbody></table>
${terms ? `<p>${escape(terms)}</p>` : ''}
</html>
`;
}

export function pdfFromHtml(html) {
  const browser = process.env.KAITO_MONEY_CHROME || [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
    'chromium', 'chromium-browser', 'google-chrome',
  ].find((candidate) => {
    if (path.isAbsolute(candidate)) return fs.existsSync(candidate);
    return (process.env.PATH ?? '').split(path.delimiter).some((dir) => fs.existsSync(path.join(dir, candidate)));
  });
  if (!browser) fail(EXIT.human, 'install Chrome or Chromium, or set KAITO_MONEY_CHROME');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kaito-money-pdf-'));
  try {
    const source = path.join(dir, 'document.html');
    const output = path.join(dir, 'document.pdf');
    fs.writeFileSync(source, html, { mode: 0o600 });
    const flags = ['--headless', '--disable-gpu', '--disable-background-networking', '--disable-component-update',
      '--disable-sync', '--no-first-run', '--no-default-browser-check', '--host-resolver-rules=MAP * ~NOTFOUND',
      '--no-pdf-header-footer', `--user-data-dir=${path.join(dir, 'profile')}`, `--print-to-pdf=${output}`];
    if (process.getuid?.() === 0) flags.push('--no-sandbox');
    const result = spawnSync(browser, [...flags, pathToFileURL(source).href], { timeout: 45000, killSignal: 'SIGKILL' });
    if (result.status !== 0 || !fs.existsSync(output)) fail(EXIT.error, `Chromium PDF render failed (${result.error?.code ?? result.status ?? result.signal})`);
    const bytes = fs.readFileSync(output);
    if (bytes.subarray(0, 5).toString() !== '%PDF-') fail(EXIT.error, 'Chromium did not return a PDF');
    return bytes;
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}
