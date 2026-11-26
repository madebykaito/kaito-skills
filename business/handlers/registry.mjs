import { cloudHandlers } from './cloud-registry.mjs';
import { emailHandler } from './email-send.mjs';
import { instagramInsightsDaily } from './instagram-insights.mjs';
import { instagramPublishHandlers } from './instagram-publish.mjs';
import { socialHandlers } from './social-publish.mjs';
import { EMAIL_ACTION } from '../scripts/kaito-email-policy.mjs';

export const handlers = new Map([
  ...cloudHandlers,
  ...instagramPublishHandlers,
  ...socialHandlers,
  [EMAIL_ACTION, emailHandler],
]);

// Read-only jobs use their own registry. They never claim an outbound approval.
export const dailyHandlers = new Map([['instagram-insights', instagramInsightsDaily]]);
