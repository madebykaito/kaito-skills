import { EXIT, fail, isoUtc, readOwner } from './kaito-ledger-lib.mjs';

export const EMAIL_ACTION = 'email.send';
const ENGINES = ['smtp', 'ses', 'listmonk'];
const local = "[a-z0-9!#$%&'*+/=?^_`{|}~-]+";
const label = '[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?';
const address = new RegExp(`^${local}(?:\\.${local})*@${label}(?:\\.${label})+$`, 'i');
export const isAddress = (s) => typeof s === 'string' && s.length <= 254
  && s.indexOf('@') <= 64 && address.test(s) && !/[\r\n]/.test(s);
export const isMessageId = (s) => typeof s === 'string' && s.length <= 500
  && /^<[\x21-\x3b\x3d\x3f-\x7e]+@[a-z0-9.-]+>$/i.test(s) && !/[\r\n]/.test(s);
const badHeader = /[\p{Cc}\p{Zl}\p{Zp}]/u;

function validUnsubscribe(s) {
  if (typeof s !== 'string' || /[\s<>,]/.test(s)) return false;
  if (s.startsWith('mailto:')) return isAddress(s.slice(7));
  try {
    const u = new URL(s);
    return s.startsWith('https://') && u.protocol === 'https:' && !u.username && !u.password;
  } catch { return false; }
}

export function parseEmail(text, account, attachmentCount) {
  if (!text) fail(EXIT.usage, 'email.send requires a message manifest');
  const src = text.toString('utf8');
  const sep = src.indexOf('\n\n');
  let m;
  try { m = JSON.parse(src.slice(0, sep)); } catch { /* validation below */ }
  if (sep < 0 || !m || JSON.stringify(m, null, 2) !== src.slice(0, sep)
    || m.version !== 1 || !ENGINES.includes(m.engine)
    || !isAddress(m.from) || m.from !== account || !isAddress(m.to)
    || typeof m.subject !== 'string' || !m.subject.trim() || badHeader.test(m.subject)
    || !Array.isArray(m.attachments) || m.attachments.length !== attachmentCount
    || m.attachments.some((n) => typeof n !== 'string' || !n || n === '.' || n === '..'
      || /[\/\\]/.test(n) || badHeader.test(n))
    || ![null, true].includes(m.one_click)
    || (m.unsubscribe !== null && !validUnsubscribe(m.unsubscribe))
    || (m.one_click && !m.unsubscribe?.startsWith('https://'))
    || (m.in_reply_to !== null && !isMessageId(m.in_reply_to))
    || (m.engine === 'listmonk'
      ? !Number.isSafeInteger(m.template) || m.template < 1 || m.to !== m.to.toLowerCase()
      : m.template !== null)) {
    fail(EXIT.usage, 'invalid email envelope, headers, attachments or engine options');
  }
  const body = src.slice(sep + 2);
  if (body.includes('\0')) fail(EXIT.usage, 'email body contains a null character');
  return { ...m, body };
}

export function dncBlocked(db, owner, to) {
  return db.prepare('SELECT 1 FROM email_do_not_contact WHERE owner = ? AND address = ?')
    .get(owner, to.toLowerCase()) !== undefined;
}

export function emailRefusal(db, owner, message, claim) {
  const record = readOwner(owner);
  if (record?.channels?.email !== message.from) return 'sender must match channels.email for this owner';
  if (dncBlocked(db, owner, message.to)) return 'recipient is on this owner’s do-not-contact list';
  if (!claim) return null;
  const { ms, opKey, ref } = claim;
  const active = db.prepare(`
    SELECT 1 FROM actions WHERE owner = ? AND action = ? AND op_key = ? AND ref <> ?
      AND state IN ('claimed', 'sent', 'uncertain', 'reconciled')
    LIMIT 1
  `).get(owner, EMAIL_ACTION, opKey, ref);
  if (active) return 'an attempt for this email is active or has already been accepted';
  const limit = record.email_rate_per_hour ?? 30;
  if (!Number.isSafeInteger(limit) || limit < 1) return 'invalid email_rate_per_hour for this owner';
  const { used } = db.prepare(`
    SELECT count(*) AS used FROM actions AS a JOIN attempts AS t ON t.ref = a.ref
    WHERE a.owner = ? AND a.action = ? AND t.claimed_at > ?
  `).get(owner, EMAIL_ACTION, isoUtc(ms - 3600_000));
  return used >= limit ? 'owner email rate limit reached (rolling hour)' : null;
}
