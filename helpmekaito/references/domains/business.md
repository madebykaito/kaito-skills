# Business

Work done for a brand the user runs: sales, marketing, promotions, content, publishing, money and support. Every route here starts with the owner. Before anything else, step 0 of the router runs `kaito-owner.mjs resolve` and passes `--owner <id>` to memory; on `ambiguous` it stops and asks.

| Skill | Use when | Not when |
|---|---|---|
| `social-publish` | Publish or schedule an approved LinkedIn, X or YouTube post through Postiz, after `business`. | Instagram, email, or drafting without publishing. |
| `business` | The work is for one owner's brand: a post, a cold email, a campaign, a quote or invoice, a payment chase, a support reply, "what needs me today"; or the user adds, lists, shows or binds owners. Loads first in every business chain: it names the owner and holds the approval rules. | Copy, design or code with no brand behind it (a page for this repo's own product, a README): route by craft alone. |
| `reel-assemble` | Assemble an owner’s shots, voice, captions and music or check a delivery file. Pair with `business` first. | Publishing a finished video. |
| `shortform-video` | Generate an owner’s short from a topic through MoneyPrinterTurbo. Pair with `business` first. | Publishing or generic media without an owner. |
| `business` | Schedule an approved action, pull daily insights, or sync sales leads with Twenty. | Drafting the payload or qualifying new leads. |
| `instagram-publish` | Publish, schedule or reconcile an Instagram image, Reel, Story or carousel for the owner. Pair with `business` for approval. | Drafting captions or making media. |
| `instagram-insights` | Pull or review Instagram account and media metrics for the owner. | Website analytics or general reporting. |
| `email-send` | Draft an owner email for approval, send an approved email, or manage unsubscribe and do-not-contact entries. | Generic copywriting or inbox triage. |
| `support-inbox` | Triage a support mailbox, queue customer follow-ups, or draft FAQ replies. Pair with `email-send` to propose a reply. | Generic email delivery or copywriting. |
| `sales-qualify` | Qualify a lead and record its account brief. | Drafting outreach before qualification. |
| `sales-outreach` | Draft outreach or follow-up for a qualified lead. | Sending email. |
| `sales-review` | Review the exact sales draft or proposal before sending. | General code review. |
| `sales-retro` | Record a sales outcome and lessons. | Marketing metrics retros. |
| `marketing-brief` | Set the buyer, message, proof, action and target before drafting marketing. | Reviewing or measuring an existing piece. |
| `marketing-review` | Check a marketing draft against its agreed brief and evidence. | Drafting a new brief or evaluating results. |
| `marketing-retro` | Compare real marketing results with the brief and record lessons. | Reviewing an unpublished draft. |
| `money` | Draft, check or issue a quote, GST invoice or credit note. Record payments, review aging or prepare payment reminders. | Contracts, NDAs or legal review. |
| `channel-retro` | Review an owner’s weekly website and Instagram metrics together. | Generic analytics with no owner. |
| `voiceover` | Generate speech for the owner’s script. | Captioning existing audio. |
| `captions` | Render timed captions or transcribe existing video. | Writing or generating spoken lines. |
| `keyframes` | Generate stills for a planned shot. | Animating a still. |
| `local-video` | Render, animate or upscale local clips. | Assembling the complete Reel. |
| `music` | Generate a background music bed locally. | Writing narration. |
| `media-cleanup` | Keep the final media and inputs needed to rebuild it. | Editing or publishing the final media. |
| `marketing-plan` | Plan campaign goals, budget, channels and measurement. | Briefing a single asset. |
| `cold-email` | Write first-contact email copy. | Qualifying the lead or sending the email. |
| `prospecting` | Find accounts that fit the owner’s audience. | Moving an existing lead through sales stages. |
| `social` | Draft organic social content. | Publishing a finished post. |
| `emails` | Plan lifecycle and campaign email content. | Sending an approved email. |
| `launch` | Plan launch timing and channel coordination. | Delivering individual messages. |
| `lead-magnets` | Plan a resource to earn sign-ups. | Preparing individual prospect outreach. |
| `referrals` | Design a referral program. | Qualifying a referred lead. |
| `ads` | Plan paid distribution. | Writing the creative. |
| `ad-creative` | Draft and test ad concepts. | Setting bids or budgets. |
| `influencer-marketing` | Plan creator partnerships. | Publishing the approved content. |
| `ab-testing` | Design a controlled experiment. | Reporting a campaign’s observed results. |
| `churn-prevention` | Plan how to retain customers. | Triaging individual customer messages. |

## Overlap rules

- **Craft plus owner.** A craft skill (`copywriting`, `ogilvy`, `copy-editing`, `stop-slop`, `content-strategy`, `cro`, `brandkit`, `banner-design`, the higgsfield skills) writes or designs; `business` decides whose voice, brand, offers and claims apply. When the request names an owner or runs in a bound folder ("write a cold email for Lumen Tea"), route `business` first, then the craft skill. A craft skill alone would write in no one's voice.
- **Outbound goes through the ledger.** Posting, sending, scheduling or publishing ("post this reel", "send this to the list", "schedule it for Friday") is `business` first: resolve the owner, then propose the exact payload to the ledger and wait for the founder's approval. Use `instagram-publish`, `social-publish` or `email-send` according to the channel.
- **Quotes and invoices.** Start with `business`, then load `money` for the document, GST, payments or collections. "Draft an invoice" goes to `business`, never to `legal:review-contract`. Use `legal:*` for contracts and NDAs, and pair `legal:review-contract` with `money` when a quote contains a contract clause.
- **Studio is craft, the owner still comes first.** Voiceover, captions, keyframes and reels for an owner start with `business` for the owner's voice, likeness consent and engine rules, then the studio or video skill ([video.md](video.md), [media.md](media.md)). Generic media with no owner routes there directly.
- **Strategy for this repo is engineering.** Planning, shipping or reviewing the code of the business tools themselves is [engineering.md](engineering.md), not this file.
- **Two owners in one request.** Run `business` once per owner, one output each. If both must act at once, ask the user to open a second session.

Pairs:
- A cold email or outreach message for an owner: `business`, then `sales-qualify` and `sales-outreach`, followed by `sales-review` and `email-send` for sending.
- A support reply: `business`, then `support-inbox`, then `email-send` for the exact reply proposal and delivery.
- A post for an owner: `business`, then `copywriting` (or `ogilvy` for an ad), then the ledger proposal from `business`.
- An Instagram post for an owner: `business`, then `instagram-publish` for the proposal and delivery.
- A payment reminder: `business`, then `money` to check the balance, then `email-send` for the exact reminder and delivery.
- A campaign: follow the [campaign recipe](../recipes.md#campaign). Use `marketing-retro` for the brief’s result and `channel-retro` for the weekly cross-channel view.
- A brand visual for an owner: `business`, then `brandkit` or `banner-design`.
