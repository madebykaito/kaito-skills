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

Pairs:
- An audit that finds missing structured data: `seo-audit`, then `schema`.
- A plan, then pages: `content-strategy`, then `programmatic-seo` or `competitors`.
- `cro` changes need measuring: add `analytics` if no tracking exists.

Model note: `programmatic-seo` page generation is bulk work. Design the template in the main session, then delegate the page fill to a light tier.
