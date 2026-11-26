import {
  EXIT, fail, getAction, openDb, readVerified, STALE_CLAIM_MS, tx, verifyAction,
} from '../scripts/kaito-ledger-lib.mjs';

export const isPostizAction = (action) => /^social\.(linkedin|linkedin-page|x|youtube)\.publish$/.test(action);

export function verifiedItem(row) {
  if (verifyAction(row).problems.length) fail(EXIT.human, 'approved payload changed');
  return {
    ...row, idempotency_key: row.op_key,
    text: row.text_sha256 ? readVerified(row.text_sha256) : null,
    media: JSON.parse(row.media_json).map(readVerified),
  };
}

export function activeAttempt(db, ref, digest, attempt) {
  const claimed = db.prepare('SELECT claimed_at FROM attempts WHERE ref = ? AND digest = ? AND n = ? AND result IS NULL')
    .get(ref, digest, attempt);
  if (!claimed || Date.parse(claimed.claimed_at) + STALE_CLAIM_MS <= Date.now()) {
    fail(EXIT.human, 'dispatch requires an active ledger claim');
  }
}

export function consumeDispatch(ref, digest, attempt, accepts, validate) {
  const db = openDb();
  try {
    return tx(db, () => {
      const row = getAction(db, ref);
      if (row.state !== 'claimed' || row.digest !== digest || !accepts(row.action)) {
        fail(EXIT.human, 'dispatch requires an active ledger claim for this action and digest');
      }
      activeAttempt(db, ref, digest, attempt);
      const reservation = db.prepare(`UPDATE dispatch_reservations SET consumed_at = ?
        WHERE ref = ? AND attempt = ? AND consumed_at IS NULL RETURNING allow_cloud`).get(Date.now(), ref, attempt);
      if (!reservation) fail(EXIT.human, 'dispatch reservation is unavailable or already used');
      const item = { ...verifiedItem(row), attempt, allowCloud: reservation.allow_cloud === 1 };
      validate?.(db, item);
      return item;
    });
  } finally { db.close(); }
}

export function recordDispatchIntent(item, checkDeadline) {
  const db = openDb();
  try {
    tx(db, () => {
      checkDeadline();
      if (getAction(db, item.ref).state !== 'claimed') fail(EXIT.human, 'dispatch claim is no longer active');
      activeAttempt(db, item.ref, item.digest, item.attempt);
      const result = db.prepare(`UPDATE dispatch_reservations SET intent_at = ?
        WHERE ref = ? AND attempt = ? AND consumed_at IS NOT NULL AND intent_at IS NULL`)
        .run(Date.now(), item.ref, item.attempt);
      if (result.changes !== 1) fail(EXIT.human, 'dispatch intent could not be recorded');
    });
  } finally { db.close(); }
}

export function unresolvedPostizDispatch(db, row) {
  return isPostizAction(row.action) && !!db.prepare('SELECT 1 FROM dispatch_reservations WHERE ref = ? AND intent_at IS NOT NULL').get(row.ref);
}
