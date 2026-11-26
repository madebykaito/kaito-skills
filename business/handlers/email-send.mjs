import { parseEmail } from '../scripts/kaito-email-policy.mjs';
import { EXIT, fail, readOwner } from '../scripts/kaito-ledger-lib.mjs';
import { readMailKey, requireMailConsent, runMailPython } from '../scripts/kaito-mail-runtime.mjs';

export function prepareEmail(item, allowCloud) {
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

export const emailHandler = {
  publish(item, { allowCloud } = {}) {
    let prepared;
    try { prepared = prepareEmail(item, allowCloud); }
    catch { return { result: 'failed', note: 'email configuration or engine consent unavailable' }; }
    const { message, config } = prepared;
    const attachments = item.media.map(bytes => bytes.toString('base64'));
    const outcome = runMailPython('kaito-email-transport.py',
      { message, config, attachments, ref: item.ref, opKey: item.idempotency_key }, 60_000);
    let reply;
    try { if (outcome.status === 0) reply = JSON.parse(outcome.stdout); } catch { /* uncertain */ }
    const result = ['ok', 'failed', 'uncertain'].includes(reply?.result) ? reply.result
      : outcome.error?.code === 'ENOENT' ? 'failed' : 'uncertain';
    const remoteId = typeof reply?.remote === 'string' && /^[!-~]{1,250}$/.test(reply.remote) ? reply.remote : null;
    return { result, remoteId, note: `${message.engine} ${result}` };
  },
};
