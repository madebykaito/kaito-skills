# Engineering: workflow, review, performance

## Dev workflow

`gstack` is its own router with its own rules. Hand off, do not re-route.

Send to `gstack` when the request is about: planning or reviewing a plan, QA and browser testing, code review of a diff, shipping and PRs, security audit, docs after a release, retros, saving or restoring context, PDFs, scraping a page. Invoke `/gstack` with the user's request and let it pick the sub-skill. If the user named a gstack sub-skill (`/qa`, `/ship`, `/review`, `/cso`), invoke that directly.

`gstack` needs bun and its own `./setup`. If its sub-skills are not in the available-skills list, say so and do the work directly.

## Code review

| Skill | Use when |
|---|---|
| `adversarial-review` | A deep, skeptical review of a diff, PR or branch: assume it is broken and report only what survives refutation. |
| `gstack` `/review` | A standard pre-landing review. |

`adversarial-review` scales to a multi-agent fan-out. That is where cross-vendor models help most: see [models.md](../models.md).

Interface quality of a change is `interface-review` in [interface-rules.md](interface-rules.md), not code review.

## Performance and architecture

| Skill | Use when |
|---|---|
| `conductor-rewrite-performance` | A local-first React desktop app (Tauri, Electron) with re-render cascades or slow streaming lists. |
| `linear-local-first-architecture` | Designing a web app that must feel instant: local-first sync, optimistic updates, no spinners. |
| `vercel-react-best-practices` | React and Next.js web performance. Listed in [frontend.md](frontend.md). |

Overlap rule: `linear-local-first-architecture` is design. `conductor-rewrite-performance` is profiling and fixing. Slow because of the network is the first. Slow because of rendering is the second.
