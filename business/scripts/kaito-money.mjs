#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import {
  EXIT, fail, run, parseArgs, only, openDb, tx, isoUtc, localParts, readOwner, checkOwnerId,
  ownerTz, kaitoHome, isSha, readVerified, getAction,
} from './kaito-ledger-lib.mjs';
import { proposeAction, claimDocument, recordAction, rejectAction } from './kaito-ledger.mjs';
import { ACTIONS, TITLES, day, documentPayload, inr, jsonFile, pdfFromHtml, renderHtml, text } from './kaito-money-document.mjs';

const USAGE = `usage: kaito-money.mjs <command> --owner <id>
  draft invoice|quote --input <json>
  check <id> [--html <file>] [--pdf <file>]
  revise <id> --input <json>
  credit <issued-invoice-id> --reason <text>
  propose <id> --account <billing-channel> [--pdf]
  issue <id> --ref <ref> --digest <sha256>
  export <issued-id> [--html <file>] [--pdf <file>]
  payment <issued-invoice-id> --paise <integer> --reference <receipt-id>
  aging [--as-of <YYYY-MM-DD> | --sync]
  chase <issued-invoice-id>`;

function save(db, owner, kind, payload, { previous_id = null, original_id = null } = {}) {
  const id = randomUUID();
  db.prepare('INSERT INTO money_documents VALUES (?, ?, ?, ?, ?, ?)').run(id, owner, kind, previous_id, original_id, JSON.stringify(payload));
  return { id, owner, kind, previous_id, original_id, payload };
}

function load(db, owner, id) {
  const row = db.prepare('SELECT * FROM money_documents WHERE owner = ? AND id = ?').get(owner, id);
  if (!row) fail(EXIT.notFound, 'document not found for this owner');
  return { ...row, payload: JSON.parse(row.payload) };
}

function issued(db, id) {
  return db.prepare(`SELECT i.*, p.issue_date FROM money_issues i
    JOIN money_proposals p ON p.ref = i.ref WHERE i.document_id = ?`).get(id);
}

function active(db, doc) {
  if (issued(db, doc.id)) fail(EXIT.human, 'document already issued');
  if (db.prepare('SELECT 1 FROM money_documents WHERE previous_id = ?').get(doc.id)) fail(EXIT.human, 'revision superseded');
  if (doc.original_id && db.prepare('SELECT 1 FROM money_issues WHERE original_id = ?').get(doc.original_id)) {
    fail(EXIT.human, 'invoice already credited');
  }
}

function retiredProposals(db, doc, keep) {
  const refs = db.prepare(`SELECT a.ref FROM actions a JOIN money_proposals p ON p.ref = a.ref
    WHERE p.document_id = ? AND a.ref <> ? AND a.state IN ('proposed', 'approved')`).all(doc, keep ?? '');
  for (const { ref } of refs) rejectAction(db, ref, 'Superseded by the Money workflow');
}

function payloadFor(input, owner, kind) {
  const config = jsonFile(path.join(kaitoHome(), 'owners', owner.id, 'money.json'));
  return documentPayload(jsonFile(input), owner, config, kind);
}

function draft(db, owner, kind, args) {
  if (!['invoice', 'quote'].includes(kind)) fail(EXIT.usage, 'draft needs invoice or quote');
  const payload = payloadFor(args.input, owner, kind);
  return tx(db, () => save(db, owner.id, kind, payload));
}

function revise(db, owner, doc, args) {
  return tx(db, () => {
    active(db, doc);
    if (doc.kind === 'credit') fail(EXIT.human, 'create a new credit note draft with the corrected reason');
    const revision = save(db, owner.id, doc.kind, payloadFor(args.input, owner, doc.kind), { previous_id: doc.id });
    retiredProposals(db, doc.id);
    return revision;
  });
}

function credit(db, doc, args) {
  const reason = text(args.reason, 'credit reason');
  return tx(db, () => {
    const original = issued(db, doc.id);
    if (!original || doc.kind !== 'invoice') fail(EXIT.human, 'credit needs an issued invoice');
    if (db.prepare('SELECT 1 FROM money_issues WHERE original_id = ?').get(doc.id)) fail(EXIT.human, 'invoice already credited');
    const payload = {
      ...doc.payload, due_date: null, terms: null,
      credit: { number: original.number, date: original.issue_date, reason },
    };
    return save(db, doc.owner, 'credit', payload, { original_id: doc.id });
  });
}

function candidate(db, doc, date) {
  const [year, month] = date.split('-').map(Number);
  const fy = month < 4 ? year - 1 : year;
  const { sequence } = db.prepare(`SELECT coalesce(max(sequence), 0) + 1 AS sequence FROM money_issues
    WHERE owner = ? AND kind = ? AND financial_year = ?`).get(doc.owner, doc.kind, fy);
  if (sequence > 999999) fail(EXIT.human, 'document series exhausted for this financial year');
  const prefix = { quote: 'Q', invoice: 'INV', credit: 'CN' }[doc.kind];
  return { date, fy, sequence, number: `${prefix}-${fy}-${String(sequence).padStart(6, '0')}` };
}

// The Indian financial calendar is independent of the owner's reminder timezone.
const issueDate = (ms = Date.now()) => localParts(ms, 'Asia/Kolkata').date;
const ownerDate = (owner) => localParts(Date.now(), ownerTz(owner)).date;

function propose(db, doc, args) {
  active(db, doc);
  const current = candidate(db, doc, issueDate());
  const html = renderHtml(doc, current);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kaito-money-issue-'));
  try {
    const summary = path.join(dir, 'approval.txt');
    const htmlFile = path.join(dir, 'document.html');
    const pdfFile = path.join(dir, 'document.pdf');
    fs.writeFileSync(htmlFile, html, { mode: 0o600 });
    if (args.pdf) fs.writeFileSync(pdfFile, pdfFromHtml(html), { mode: 0o600 });
    fs.writeFileSync(summary, [
      `${TITLES[doc.kind]} ${current.number} dated ${current.date}`,
      `From ${doc.payload.issuer.name} to ${doc.payload.client.name}`,
      `Total ${inr(doc.payload.totals.total)}`,
      `Review the attached HTML${args.pdf ? ' and PDF' : ''} before approving local issue.`,
    ].join('\n') + '\n', { mode: 0o600 });
    const approval = proposeAction({
      owner: doc.owner, account: args.account, action: ACTIONS[doc.kind],
      'text-file': summary, media: args.pdf ? [htmlFile, pdfFile] : [htmlFile],
    }, (db, ref) => {
      active(db, doc);
      const fresh = candidate(db, doc, issueDate());
      if (fresh.date !== current.date || fresh.sequence !== current.sequence) {
        fail(EXIT.human, 'candidate went stale while rendering, propose again');
      }
      db.prepare('INSERT INTO money_proposals VALUES (?, ?, ?, ?)').run(ref, doc.id, current.date, current.sequence);
      retiredProposals(db, doc.id, ref);
    });
    return { ...approval, candidate: current.number, issue_date: current.date };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function closeChase(db, invoice) {
  db.prepare(`UPDATE queue_items SET state = 'closed', closed_at = ?
    WHERE id = (SELECT queue_id FROM money_chases WHERE invoice_id = ?) AND state = 'open'`)
    .run(isoUtc(Date.now()), invoice);
}

function issue(db, doc, args) {
  if (!args.ref || !isSha(args.digest)) fail(EXIT.usage, 'issue needs --ref and the full --digest');
  const outcome = tx(db, () => {
    const proposal = db.prepare('SELECT * FROM money_proposals WHERE ref = ? AND document_id = ?').get(args.ref, doc.id);
    if (!proposal) fail(EXIT.human, 'approval ref does not belong to this revision');
    const action = getAction(db, args.ref);
    if (action.owner !== doc.owner || action.action !== ACTIONS[doc.kind] || action.digest !== args.digest) {
      fail(EXIT.human, 'approval owner, action or digest differs');
    }
    const prior = issued(db, doc.id);
    if (prior?.ref === args.ref) return { issue: prior };
    active(db, doc);
    const ms = Date.now();
    const next = candidate(db, doc, issueDate(ms));
    if (proposal.issue_date !== next.date || proposal.sequence !== next.sequence) {
      fail(EXIT.human, 'candidate date or number went stale, propose again and get a new approval');
    }
    const claim = claimDocument(db, args.ref, args.digest, ms);
    if (claim.refused) return claim;
    db.prepare(`INSERT INTO money_issues
      (document_id, ref, owner, kind, financial_year, sequence, number, original_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)`).run(doc.id, args.ref, doc.owner, doc.kind, next.fy, next.sequence, next.number, doc.original_id);
    if (doc.original_id) closeChase(db, doc.original_id);
    retiredProposals(db, doc.id, args.ref);
    const recorded = recordAction(db, args.ref, claim.n, 'ok', next.number);
    if (recorded.err) fail(...recorded.err);
    return { issue: issued(db, doc.id) };
  });
  if (outcome.refused) fail(EXIT.human, `refused: ${outcome.refused}`);
  return outcome.issue;
}

function writeOutputs(outputs) {
  const created = [];
  try {
    for (const [file, bytes] of outputs) {
      const fd = fs.openSync(file, 'wx', 0o600);
      created.push(file);
      try { fs.writeFileSync(fd, bytes); } finally { fs.closeSync(fd); }
    }
  } catch (error) {
    for (const file of created) fs.rmSync(file, { force: true });
    if (error.code === 'EEXIST') fail(EXIT.human, 'output already exists, choose a new path');
    throw error;
  }
}

function check(db, doc, args) {
  const info = issued(db, doc.id);
  if (info && (args.html || args.pdf)) fail(EXIT.human, 'use export to copy issued artifacts');
  if (args.html || args.pdf) {
    const html = renderHtml(doc, null);
    const outputs = [];
    if (args.html) outputs.push([args.html, html]);
    if (args.pdf) outputs.push([args.pdf, pdfFromHtml(html)]);
    writeOutputs(outputs);
  }
  return {
    id: doc.id, kind: doc.kind, previous_id: doc.previous_id, original_id: doc.original_id,
    mode: doc.payload.mode, place_of_supply: doc.payload.place_of_supply, totals: doc.payload.totals,
    issue: info ?? null,
  };
}

function exportIssued(db, doc, args) {
  const info = issued(db, doc.id);
  if (!info) fail(EXIT.human, 'document has not been issued');
  if (!args.html && !args.pdf) fail(EXIT.usage, 'export needs --html or --pdf');
  const { media_json } = getAction(db, info.ref);
  const [html, pdf] = JSON.parse(media_json);
  if (args.pdf && !pdf) fail(EXIT.human, 'the approval covered HTML only');
  const outputs = [];
  if (args.html) outputs.push([args.html, readVerified(html)]);
  if (args.pdf) outputs.push([args.pdf, readVerified(pdf)]);
  writeOutputs(outputs);
  return info;
}

const BALANCE = `CAST(json_extract(d.payload, '$.totals.total') AS INTEGER) -
  coalesce((SELECT sum(p.paise) FROM money_payments p WHERE p.invoice_id = d.id), 0)`;

function invoiceBalance(db, doc) {
  if (doc.kind !== 'invoice' || !issued(db, doc.id)) fail(EXIT.human, 'an issued invoice is required');
  return db.prepare(`SELECT ${BALANCE} AS paise, EXISTS (
    SELECT 1 FROM money_issues WHERE original_id = d.id) AS credited
    FROM money_documents d WHERE d.id = ?`).get(doc.id);
}

function payment(db, doc, args) {
  const reference = text(args.reference, 'payment reference', 128);
  const amount = Number(args.paise);
  if (!/^\d+$/.test(args.paise ?? '') || !Number.isSafeInteger(amount) || amount < 1) fail(EXIT.usage, '--paise needs a positive integer');
  return tx(db, () => {
    const balance = invoiceBalance(db, doc);
    const prior = db.prepare('SELECT paise FROM money_payments WHERE invoice_id = ? AND reference = ?').get(doc.id, reference);
    if (prior && prior.paise !== amount) fail(EXIT.human, 'payment reference already has another amount');
    if (prior) return { id: doc.id, reference, balance_paise: balance.credited ? 0 : balance.paise };
    if (balance.credited || amount > balance.paise) fail(EXIT.human, 'payment exceeds the collectible balance');
    db.prepare('INSERT INTO money_payments VALUES (?, ?, ?)').run(doc.id, reference, amount);
    if (balance.paise === amount) closeChase(db, doc.id);
    return { id: doc.id, reference, balance_paise: balance.paise - amount };
  });
}

function agingRows(db, owner, date) {
  const rows = db.prepare(`SELECT d.id, i.ref, i.number, json_extract(d.payload, '$.due_date') AS due_date,
    ${BALANCE} AS balance_paise
    FROM money_issues i JOIN money_documents d ON i.document_id = d.id
    WHERE i.owner = ? AND i.kind = 'invoice'
      AND NOT EXISTS (SELECT 1 FROM money_issues WHERE original_id = d.id)
    ORDER BY due_date, i.number`).all(owner);
  return rows.filter((row) => row.balance_paise > 0 && row.due_date <= date).map((row) => {
    const days = (Date.parse(date) - Date.parse(row.due_date)) / 86400000;
    return { ...row, days, bucket: days <= 30 ? '0-30' : days <= 60 ? '31-60' : days <= 90 ? '61-90' : '90+' };
  });
}

function aging(db, owner, args) {
  if (args.sync && args['as-of']) fail(EXIT.usage, '--sync uses the current owner date');
  if (!args.sync) return agingRows(db, owner, args['as-of'] ? day(args['as-of']) : ownerDate(owner));
  return tx(db, () => {
    const rows = agingRows(db, owner, ownerDate(owner));
    for (const row of rows) {
      if (db.prepare('SELECT 1 FROM money_chases WHERE invoice_id = ?').get(row.id)) continue;
      const queue = db.prepare(`INSERT INTO queue_items (owner, kind, title, due_date, all_day, ref, note, created_at)
        VALUES (?, 'invoice-chase', ?, ?, 1, ?, ?, ?)`).run(owner, `Chase invoice ${row.number}`, row.due_date,
        row.ref, `Money document ${row.id}`, isoUtc(Date.now()));
      db.prepare('INSERT INTO money_chases VALUES (?, ?)').run(row.id, queue.lastInsertRowid);
    }
    return rows;
  });
}

function chase(db, doc) {
  const row = agingRows(db, doc.owner, ownerDate(doc.owner)).find((row) => row.id === doc.id);
  if (!row) fail(EXIT.human, 'invoice has no collectible balance due yet');
  const { issuer, client } = doc.payload;
  if (!client.email) fail(EXIT.human, 'the invoice has no client email, confirm the address before drafting in email-send');
  return {
    to: client.email, subject: `Payment reminder for ${row.number}`,
    body: `Hello ${client.name},\n\nA payment of ${inr(row.balance_paise)} is outstanding on invoice ${row.number}. It was due on ${row.due_date}. Could you confirm when we can expect payment?\n\nThank you,\n${issuer.name}\n`,
  };
}

const FLAGS = {
  draft: ['input'], revise: ['input'], credit: ['reason'], check: ['html', 'pdf'], export: ['html', 'pdf'],
  propose: ['account', 'pdf'], issue: ['ref', 'digest'], payment: ['paise', 'reference'], aging: ['as-of', 'sync'], chase: [],
};

await run((argv) => {
  const command = argv[0];
  if (!command || ['help', '--help', '-h'].includes(command)) {
    console.log(USAGE);
    return command ? EXIT.ok : EXIT.usage;
  }
  if (!Object.hasOwn(FLAGS, command)) fail(EXIT.usage, USAGE);
  const bool = command === 'propose' ? ['pdf'] : ['sync'];
  const args = parseArgs(argv, { bool });
  only(args, ['owner', ...FLAGS[command]]);
  if (args._.length !== (command === 'aging' ? 1 : 2)) fail(EXIT.usage, USAGE);
  const owner = readOwner(checkOwnerId(args.owner));
  if (!owner || owner.id !== args.owner) fail(EXIT.notFound, 'owner not found');
  const db = openDb();
  try {
    const id = args._[1];
    const commands = { revise, credit, check, export: exportIssued, propose, issue, payment, chase };
    let result;
    if (command === 'draft') result = draft(db, owner, id, args);
    else if (command === 'aging') result = aging(db, owner.id, args);
    else {
      const doc = load(db, owner.id, id);
      result = command === 'revise' ? revise(db, owner, doc, args) : commands[command](db, doc, args);
    }
    console.log(JSON.stringify(result));
  } finally {
    db.close();
  }
});
