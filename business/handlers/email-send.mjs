import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { consumeDispatch } from './dispatch.mjs';
import { EMAIL_ACTION, emailRefusal, parseEmail } from '../scripts/kaito-email-policy.mjs';
import { EXIT, fail, readOwner } from '../scripts/kaito-ledger-lib.mjs';
import { readMailKey, requireMailConsent } from '../scripts/kaito-mail-runtime.mjs';

const transport = fileURLToPath(new URL('../scripts/kaito-email-transport.py', import.meta.url));

function prepareEmail(item, allowCloud) {
  const record = readOwner(item.owner);
  if (record?.channels?.email !== item.account) fail(EXIT.human, 'email account differs from owner sender');
  const message = parseEmail(item.text, item.account, item.media.length);
  const config = readMailKey(record, message.engine);
  let host;
  try { host = message.engine === 'smtp' ? config.host : new URL(config.url).hostname; } catch { /* invalid URL */ }
  if (message.engine === 'ses' || (message.engine === 'smtp' && config.tls !== 'none')
      || !['127.0.0.1', '::1', '[::1]', 'localhost'].includes(host)) {
    requireMailConsent(item.owner, message.engine, { 'allow-cloud': allowCloud });
  }
  return { message, config };
}

export function checkEmailConfig(item, allowCloud) {
  prepareEmail(item, allowCloud);
}

export const emailHandler = {
  ledger: true,
  publish(ref, digest, attempt) {
    const item = consumeDispatch(ref, digest, attempt, (action) => action === EMAIL_ACTION, (db, row) => {
      const why = emailRefusal(db, row.owner, parseEmail(row.text, row.account, row.media.length));
      if (why) fail(EXIT.human, why);
    });
    let prepared;
    try { prepared = prepareEmail(item, item.allowCloud); }
    catch { return { result: 'failed', note: 'email configuration or engine consent unavailable' }; }
    const { message, config } = prepared;
    const attachments = item.media.map(bytes => bytes.toString('base64'));
    const outcome = spawnSync('python3', ['-I', transport], {
      input: JSON.stringify({ message, config, attachments, ref: item.ref, opKey: item.idempotency_key }),
      encoding: 'utf8', timeout: 60_000, maxBuffer: 32 * 1024 * 1024, stdio: ['pipe', 'pipe', 'ignore'],
    });
    let reply;
    try { if (outcome.status === 0) reply = JSON.parse(outcome.stdout); } catch { /* uncertain */ }
    const result = ['ok', 'failed', 'uncertain'].includes(reply?.result) ? reply.result
      : outcome.error?.code === 'ENOENT' ? 'failed' : 'uncertain';
    const remoteId = typeof reply?.remote === 'string' && /^[!-~]{1,250}$/.test(reply.remote) ? reply.remote : null;
    return { result, remoteId, note: `${message.engine} ${result}` };
  },
};
