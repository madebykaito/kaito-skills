#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  EXIT, fail, run, parseArgs, only, printKv, canonicalText, readVerified, openDb, getAction, isoUtc, isSha, tx,
} from './kaito-ledger-lib.mjs';
import { EMAIL_ACTION, isAddress, parseEmail } from './kaito-email-policy.mjs';
import { businessCommand, resolveMailOwner } from './kaito-mail-runtime.mjs';
import { checkEmailConfig, emailHandler } from '../handlers/email-send.mjs';
import { claimAction, recordResult } from './kaito-ledger.mjs';

const USAGE = `usage: kaito-email.mjs [draft|propose] [--owner id] --to address --subject text --body-file file
  [--engine smtp|ses|listmonk] [--attach file ...] [--unsubscribe https://...|mailto:...] [--one-click]
  [--in-reply-to '<message-id>'] [--template id]
  propose also accepts [--due time] [--retry-of ref]
  kaito-email.mjs send <ref> --digest sha256 [--owner id] [--allow-cloud]
  kaito-email.mjs dnc add|remove <address> [--owner id] | dnc list [--owner id]`;

function makeDraft(args, owner, record, propose) {
  only(args, ['owner', 'to', 'subject', 'body-file', 'engine', 'attach', 'unsubscribe', 'one-click',
    'in-reply-to', 'template', ...(propose ? ['due', 'retry-of'] : [])]);
  if (!isAddress(record.channels?.email)) fail(EXIT.human, 'set channels.email to the sender in owner.json');
  if (!args['body-file']) fail(EXIT.usage, '--body-file is required');
  let body;
  try { body = fs.readFileSync(args['body-file']); } catch { fail(EXIT.notFound, 'cannot read body file'); }
  const files = args.attach ?? [];
  const engine = args.engine ?? 'smtp';
  if (engine === 'listmonk' && !/^[1-9][0-9]*$/.test(args.template ?? '')) fail(EXIT.usage, 'listmonk needs --template <id>');
  const manifest = {
    version: 1, from: record.channels.email, to: args.to, subject: args.subject, engine,
    unsubscribe: args.unsubscribe ?? null, one_click: args['one-click'] ?? null,
    in_reply_to: args['in-reply-to'] ?? null, template: args.template === undefined ? null : Number(args.template),
    attachments: files.map((f) => path.basename(f)),
  };
  const text = `${JSON.stringify(manifest, null, 2)}\n\n${canonicalText(body)}`;
  parseEmail(Buffer.from(text), manifest.from, files.length);
  if (!propose) { process.stdout.write(text); return; }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kaito-email-'));
  try {
    const file = path.join(dir, 'email.txt');
    fs.writeFileSync(file, text, { mode: 0o600 });
    const output = businessCommand('ledger', ['propose', '--owner', owner, '--account', manifest.from,
      '--action', EMAIL_ACTION, '--text-file', file, ...files.map((f) => `--media=${path.resolve(f)}`),
      ...(args.due ? ['--due', args.due] : []), ...(args['retry-of'] ? ['--retry-of', args['retry-of']] : [])]);
    process.stdout.write(output);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

async function send(args, owner) {
  only(args, ['owner', 'digest', 'allow-cloud']);
  if (args._.length !== 2 || !isSha(args.digest)) fail(EXIT.usage, 'send needs a ref and full --digest');
  const ref = args._[1];
  const db = openDb();
  try {
    const row = getAction(db, ref);
    if (row.owner !== owner || row.action !== EMAIL_ACTION) fail(EXIT.human, 'ref is outside this owner’s email actions');
    const allowCloud = !!args['allow-cloud'];
    const claim = claimAction(db, ref, args.digest, {
      allowCloud,
      // A missing engine or consent leaves the action approved so it can be configured.
      onClaim: () => checkEmailConfig({
        ...row, text: readVerified(row.text_sha256), media: JSON.parse(row.media_json),
      }, allowCloud),
    });
    const out = await emailHandler.publish(ref, args.digest, claim.attempt);
    printKv({ ref, state: recordResult(db, ref, claim.attempt, out.result, out.remoteId, out.note) });
    if (out.result === 'failed') fail(EXIT.error, 'email was refused or its configuration is invalid');
    if (out.result === 'uncertain') fail(EXIT.human, 'delivery is uncertain; check the provider and reconcile this ref before retrying');
  } finally { db.close(); }
}

function doNotContact(args, owner) {
  only(args, ['owner']);
  const [, verb, address] = args._;
  if (verb === 'list' && args._.length === 2) {
    const db = openDb();
    for (const row of db.prepare('SELECT address FROM email_do_not_contact WHERE owner = ? ORDER BY address').all(owner)) {
      console.log(row.address);
    }
    return;
  }
  if (!['add', 'remove'].includes(verb) || args._.length !== 3 || !isAddress(address)) {
    fail(EXIT.usage, 'dnc add|remove <address> or dnc list');
  }
  const db = openDb();
  const key = address.toLowerCase();
  tx(db, () => {
    if (verb === 'add') db.prepare('INSERT OR IGNORE INTO email_do_not_contact VALUES (?, ?, ?)').run(owner, key, isoUtc(Date.now()));
    else db.prepare('DELETE FROM email_do_not_contact WHERE owner = ? AND address = ?').run(owner, key);
  });
  printKv({ owner, address: key, state: verb === 'add' ? 'blocked' : 'removed' });
}

await run((argv) => {
  if (argv.length === 1 && ['-h', '--help', 'help'].includes(argv[0])) { console.log(USAGE); return; }
  const args = parseArgs(argv, { multi: ['attach'], bool: ['one-click', 'allow-cloud'] });
  const [command = 'draft'] = args._;
  if (!['draft', 'propose', 'send', 'dnc'].includes(command)) fail(EXIT.usage, USAGE);
  const { owner, record } = resolveMailOwner(args.owner);
  if (command === 'send') return send(args, owner);
  if (command === 'dnc') return doNotContact(args, owner);
  if (args._.length > 1) fail(EXIT.usage, USAGE);
  return makeDraft(args, owner, record, command === 'propose');
});
