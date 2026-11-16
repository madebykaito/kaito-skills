# Engineering: workflow, review, performance

## Dev workflow (gstack)

Route straight to these gstack sub-skills. For a gstack job not listed here, hand the request to the `gstack` router. gstack needs bun; if its skills are missing, say "run ./setup in kaito-skills" and do the work directly.

| Skill | Use when |
|---|---|
| `office-hours` | Testing an idea or a startup plan before any code. |
| `spec` | Turning vague intent into an executable spec. |
| `plan-eng-review` | Reviewing a plan for architecture, edge cases and tests. |
| `plan-ceo-review` | Reviewing a plan for scope and ambition. Has hooks. |
| `plan-design-review` | Reviewing a plan's UI and UX before building. |
| `autoplan` | Running all plan reviews in one go. Has hooks. |
| `qa` | Testing a site, API or CLI and fixing what breaks. |
| `qa-only` | Testing and reporting bugs without fixing them. |
| `browse` | Driving a real browser: open, click through, screenshot, read the console. |
| `ios-qa` | QA on a live iOS device for a SwiftUI app. |
| `ios-fix` | Fixing an iOS bug end to end. |
| `verify` | Running the checks and tests until green while coding. |
| `review` | A standard pre-landing review of a diff. |
| `cso` | A security audit. |
| `health` | A code quality dashboard for the repo. |
| `ship` | Merge base, test, review, bump version, push and open a PR. |
| `document-release` | Updating docs after a release. |
| `retro` | A weekly engineering retrospective. |
| `make-pdf` | Turning markdown into a polished PDF. |
| `careful` | Warnings before destructive commands. Has hooks. |
| `freeze` | Limiting edits to one folder. Has hooks. |
| `guard` | `careful` plus `freeze`. Has hooks. |

Skills with hooks run only through the Skill tool, so only on Claude.

## Code review

| Skill | Use when |
|---|---|
| `adversarial-review` | A deep, skeptical review of a diff, PR or branch: assume it is broken and report only what survives refutation. |
| `review` | A standard pre-landing review. Listed above. |
| `ponytail-review` | A review for over-engineering only: what to delete, what stdlib replaces it. |

Overlap rule: `review` checks a diff is safe to land. `adversarial-review` tries to break it. `ponytail-review` only asks what can be cut, never correctness. "Is this over-engineered" or "what can we delete" is `ponytail-review`. "Will this break" is `adversarial-review`. Otherwise `review`.

`adversarial-review` scales to a multi-agent fan-out. That is where cross-vendor models help most: see [models.md](../models.md).

Interface quality of a change is `interface-review` in [interface-rules.md](interface-rules.md), not code review.

## Debugging, tests, branches

| Skill | Use when |
|---|---|
| `systematic-debugging` | A bug, failing test or odd behavior with an unknown cause: find the root cause before any fix. |
| `test-driven-development` | Building a feature or fix test-first. |
| `using-git-worktrees` | Starting work that needs its own branch and folder, kept apart from the current checkout. |

Overlap rule: gstack has no debugging skill of its own. A bug with an unknown cause is `systematic-debugging`. Bugs found by testing a running site are `qa`, which fixes as it goes.

## Keeping code small (ponytail)

| Skill | Use when |
|---|---|
| `ponytail` | The user wants the leanest working code: reuse, stdlib, shortest diff. A mode that stays on. |
| `ponytail-review` | Over-engineering review of a diff. Listed above. |
| `ponytail-audit` | Over-engineering audit of a whole repo, not one diff. |
| `ponytail-debt` | Collecting the `ponytail:` shortcut comments into a debt list. |

## Performance and architecture

| Skill | Use when |
|---|---|
| `conductor-rewrite-performance` | A local-first React desktop app (Tauri, Electron) with re-render cascades or slow streaming lists. |
| `linear-local-first-architecture` | Designing a web app that must feel instant: local-first sync, optimistic updates, no spinners. |
| `vercel-react-best-practices` | React and Next.js web performance. Listed in [frontend.md](frontend.md). |

Overlap rule: `linear-local-first-architecture` is design. `conductor-rewrite-performance` is profiling and fixing. Slow because of the network is the first. Slow because of rendering is the second.
