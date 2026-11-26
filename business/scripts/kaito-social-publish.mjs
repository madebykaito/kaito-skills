#!/usr/bin/env node
import { socialHandlers } from '../handlers/social-publish.mjs';
import { claimAction, recordResult } from './kaito-ledger.mjs';
import { EXIT, fail, getAction, isSha, openDb, run } from './kaito-ledger-lib.mjs';

await run(async ([ref, flag, digest, ...rest]) => {
  if (!ref || flag !== '--digest' || !isSha(digest) || rest.length) {
    fail(EXIT.usage, 'usage: kaito-social-publish.mjs <ref> --digest <sha256>');
  }
  const db = openDb();
  try {
    const handler = socialHandlers.get(getAction(db, ref).action);
    if (!handler) fail(EXIT.usage, 'not a social publish action');
    const claim = claimAction(db, ref, digest);
    const out = await handler.publish(ref, digest, claim.attempt);
    recordResult(db, ref, claim.attempt, out.result, out.remoteId, out.note);
    if (out.result !== 'ok') fail(EXIT.error, out.note ?? `Postiz ${out.result}`);
    console.log(JSON.stringify({ ref, result: out.result, remote_id: out.remoteId }));
  } finally { db.close(); }
});
