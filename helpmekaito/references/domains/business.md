# Business

Work done for a brand the user runs: sales, marketing, promotions, content, publishing, money and support. Every route here starts with the owner. Before anything else, step 0 of the router runs `kaito-owner.mjs resolve` and passes `--owner <id>` to memory; on `ambiguous` it stops and asks.

| Skill | Use when | Not when |
|---|---|---|
| `business` | The work is for one owner's brand: a post, a cold email, a campaign, a quote or invoice, a payment chase, a support reply, "what needs me today"; or the user adds, lists, shows or binds owners. Loads first in every business chain: it names the owner and holds the approval rules. | Copy, design or code with no brand behind it (a page for this repo's own product, a README): route by craft alone. |

Planned in 1.7.0 and added here as rows when they land: the sales stages (sales-qualify, sales-outreach, sales-review, sales-retro), the marketing stages (marketing-brief, marketing-review, marketing-retro), money for quotes and GST invoices, the channel publishers instagram-publish, social-publish and email-send, support-inbox, and the studio skills (voiceover, captions, keyframes, local-video, music, reel-assemble, shortform-video, media-cleanup), whose rows go in [video.md](video.md) or [media.md](media.md) with a business pair here.

## Overlap rules

Each rule says which skill wins and what pairs with it. When a later skill lands, add its row above and, if it takes over part of a rule, edit that rule to name it.

- **Craft plus owner.** A craft skill (`copywriting`, `ogilvy`, `copy-editing`, `stop-slop`, `content-strategy`, `cro`, `brandkit`, `banner-design`, the higgsfield skills) writes or designs; `business` decides whose voice, brand, offers and claims apply. When the request names an owner or runs in a bound folder ("write a cold email for Lumen Tea"), route `business` first, then the craft skill. A craft skill alone would write in no one's voice.
- **Outbound goes through the ledger.** Posting, sending, scheduling or publishing ("post this reel", "send this to the list", "schedule it for Friday") is `business` first: resolve the owner, then propose the exact payload to the ledger and wait for the founder's approval. Once the channel publishers land they do the sending, still behind the ledger. No route sends directly.
- **Money is not legal.** Quotes, invoices, GST, payment chase and aging are `business` (and the money skill once it lands). Contracts, NDAs, terms and compliance are `legal:*`. "Draft an invoice" goes to `business`, never to `legal:review-contract`. A contract clause inside a quote is the only case for both: `business` for the document, `legal:review-contract` for the clause.
- **Studio is craft, the owner still comes first.** Voiceover, captions, keyframes and reels for an owner start with `business` for the owner's voice, likeness consent and engine rules, then the studio or video skill ([video.md](video.md), [media.md](media.md)). Generic media with no owner routes there directly.
- **Strategy for this repo is engineering.** Planning, shipping or reviewing the code of the business tools themselves is [engineering.md](engineering.md), not this file.
- **Two owners in one request.** Run `business` once per owner, one output each. If both must act at once, ask the user to open a second session.

Pairs:
- A cold email or outreach message for an owner: `business`, then `copywriting`, then `stop-slop`.
- A post for an owner: `business`, then `copywriting` (or `ogilvy` for an ad), then the ledger proposal from `business`.
- A brand visual for an owner: `business`, then `brandkit` or `banner-design`.
