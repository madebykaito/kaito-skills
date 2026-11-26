# SEO and marketing

| Skill | Use when | Not when |
|---|---|---|
| `seo-audit` | Diagnosing why a site does not rank: technical SEO, on-page, meta tags. | Building new pages: `programmatic-seo`. |
| `schema` | Adding or fixing JSON-LD structured data. | A general SEO problem: `seo-audit`. |
| `programmatic-seo` | Many pages from a template and data: location, integration, directory pages. | One page. |
| `content-strategy` | Deciding what content to create: topics, clusters, a blog plan. | Writing one piece: `copywriting` in [writing.md](writing.md). |
| `competitors` | "X vs Y" and "X alternative" pages. | A general landing page. |
| `cro` | An existing marketing page or lead form does not convert. | The page does not exist yet: see [pages.md](pages.md). |
| `analytics` | Setting up or auditing GA4, GTM, events, UTMs, a tracking plan. | Reading results, which needs no skill. |
| `cold-email` | Writing unsolicited outreach to named prospects. | Email sequences: `emails`. |
| `prospecting` | Finding and qualifying potential customers. | Writing outreach: `cold-email`. |
| `social` | Social posts and channel content. | A site content plan: `content-strategy`. |
| `emails` | Welcome, nurture and lifecycle email sequences. | One cold outreach email: `cold-email`. |
| `launch` | Launch timing, channels and coordination. | The wider marketing plan: `marketing-plan`. |
| `lead-magnets` | Lead magnet ideas and conversion paths. | Finding individual prospects: `prospecting`. |
| `referrals` | Referral incentives and sharing flows. | Influencer partnerships: `influencer-marketing`. |
| `ads` | Paid channel strategy, targeting and budgets. | Individual ad variants: `ad-creative`. |
| `ad-creative` | Ad concepts, copy and creative variants. | Paid channel strategy: `ads`. |
| `influencer-marketing` | Finding and working with creators. | Customer referral programs: `referrals`. |
| `marketing-plan` | Campaign objectives, audience, channels and measurement. | A launch schedule: `launch`. |
| `ab-testing` | Hypotheses, variants and experiment measurement. | Implementing analytics: `analytics`. |
| `churn-prevention` | Cancellation flows and retention strategy. | Lifecycle email sequences alone: `emails`. |

Pairs:
- An audit that finds missing structured data: `seo-audit`, then `schema`.
- A plan, then pages: `content-strategy`, then `programmatic-seo` or `competitors`.
- `cro` changes need measuring: add `analytics` if no tracking exists.

Model note: `programmatic-seo` page generation is bulk work. Design the template in the main session, then delegate the page fill to a light tier.
