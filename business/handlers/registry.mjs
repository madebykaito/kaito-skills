import { cloudHandlers } from './cloud-registry.mjs';
import { emailHandler } from './email-send.mjs';
import { instagramInsightsDaily } from './instagram-insights.mjs';
import { instagramPublishHandlers } from './instagram-publish.mjs';
import { socialHandlers } from './social-publish.mjs';
import { EMAIL_ACTION } from '../scripts/kaito-email-policy.mjs';
import { readVerified } from '../scripts/kaito-ledger-lib.mjs';

export const handlers = new Map([
  ...cloudHandlers,
  ...instagramPublishHandlers,
  ...socialHandlers,
  [EMAIL_ACTION, emailHandler],
]);

// Read-only jobs use their own registry. They never claim an outbound approval.
export const dailyHandlers = new Map([['instagram-insights', instagramInsightsDaily]]);

export function claimedItem(claim) {
  return { ...claim, text: claim.text_sha256 ? readVerified(claim.text_sha256) : null,
    media: claim.media_sha256.map(readVerified) };
}
