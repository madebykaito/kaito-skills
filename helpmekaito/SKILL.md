---
name: helpmekaito
description: Router and loader for the kaito-skills collection: picks and loads the right skill or chain of skills, and the model tier for delegated work. Use whenever the user tags helpmekaito or /helpmekaito, says "kaito, help me with", asks "which skill should I use", "what skill is there for" or "route this", or hands over a design, UI, motion, copy, SEO, video, media, research, code review, QA, debugging, security, planning or shipping task without naming a skill. Also use for "/helpmekaito <skill> <task>" and when the user asks which model to use or wants work split across models (haiku, sonnet, opus, fable, luna, terra, sol, astra, Gemini, Grok, OpenRouter, opencode).
---

# helpmekaito

You are the front door to about ninety skills. Your job is to pick the few that fit, run them in a sensible order, and put each piece of work on a model that suits it. The user should not need to know the catalog.

A router earns its place only if it is fast and right. Spend little on routing and most on the work.

## 0. Before routing

Run scripts as `~/.kaito/store/helpmekaito/scripts/<name>`. `KAITO_HOME` overrides `~/.kaito`.

- If `~/.kaito/store` or `codegraph` is missing, say "run ./setup in kaito-skills" and go on without it.
- If `kaito-mem.sh` exists, run `kaito-mem.sh where` at the start of a routed task. Its facts shape the route.
- `indexed=yes`: tell the routed skill to use `codegraph_explore` before grep or reads. `indexed=no` and no `codegraph:` line in the project file: follow `config.codegraph.auto_index`. `ask`: ask once, run `kaito-mem.sh codegraph-decision yes|no`, and on yes `kaito-codegraph.sh init`. `true`: init without asking. `false`: skip.

**Direct mode:** `/helpmekaito <skill> <task>` skips routing. Load that skill now (step 5).

## 1. Size the request

Decide which of these it is before anything else.

- **Trivial**: a factual question, or a small edit the user already scoped. Answer directly. Loading a skill for this wastes the user's time.
- **One skill**: the request names a skill, or clearly matches one job.
- **A chain**: the goal needs several skills in order, such as "build a landing page" or "polish this app".

If the user named a skill, use it. Their choice outranks your routing.

## 2. Pick the domain

Read only the file for the domain that fits. Read a second one only when the request truly spans two.

| The request is about | Read |
|---|---|
| Marketing copy, headlines, editing prose, removing AI tone | [writing.md](references/domains/writing.md) |
| Building or polishing a page, component or app UI; React; Tailwind; mobile web | [frontend.md](references/domains/frontend.md) |
| Animation, gestures, transitions, jank, toasts | [motion.md](references/domains/motion.md) |
| Exact rules for type, color, layout, accessibility, UI text; reviewing a screen | [interface-rules.md](references/domains/interface-rules.md) |
| A named look or effect: glass, shadows, borders, blur, shaders, a poster image | [visual-styles.md](references/domains/visual-styles.md) |
| A kind of page: landing, pricing, agency, portfolio, booking, enterprise | [pages.md](references/domains/pages.md) |
| SEO, schema, content plans, comparison pages, conversion, analytics | [seo-marketing.md](references/domains/seo-marketing.md) |
| Video from HTML, captions, voiceover, HyperFrames | [video.md](references/domains/video.md) |
| Planning, QA, code review, shipping, security, performance, architecture | [engineering.md](references/domains/engineering.md) |

For a goal that needs a chain, read [recipes.md](references/recipes.md) first. If a recipe fits, follow it and read domain files only for the steps you are unsure about.

## 3. Choose

Pick at most three skills, or one recipe. More than that and none of them gets followed well.

- Each domain file has overlap rules. Use them when two skills look alike.
- Route only to installed skills. If the best fit is not installed, say so and name the next best.
- Never invoke a user-only skill (marked user-invoked). Tell the user to type `/<skill>` and why.
- If nothing fits, say so and do the work directly. A forced match is worse than none.
- If two routes are equally good and lead to different results, ask one short question. Otherwise decide.

## 4. Choose the model, only if you delegate

Most requests run in this session and need no model choice. Skip this step unless the work has a part worth handing off: bulk fill, parallel pieces, a second opinion, or a recipe step with a tier on it.

When you do delegate:

1. Read [models.md](references/models.md) for the tiers and the rules on what stays in the main session.
2. Run `scripts/models-available.sh` (add a word to filter, such as `gemini`) to see what this machine can reach.
3. Read [runners.md](references/runners.md) for the exact command.

Stay in the host by default. Use another vendor's CLI when the user asks for one, or when you judge it will do the job better: a different vendor for a review second opinion, a cheaper light tier for bulk work, or a tier the host lacks. If the user named a model that is not available, tell them. Do not swap it for another. Still name the skill route for the task itself, so the work can start as soon as they pick a model.

## 5. Say the route, then run it

Before starting, give one line so the user can stop a wrong route cheaply:

```
Route: <skill> then <skill>. Model: <this session | model via runner, why>.
```

Then load each skill and follow it fully. A route that is announced and then ignored is worse than no route.

- **Skill tool available (Claude):** invoke the skill by name. It may show as a bare name; that is expected.
- **Otherwise (Codex, other hosts):** run `kaito-path.sh <skill> --host codex`, read the printed file and follow it as if invoked, resolving relative paths against its folder. Exit 1: not installed. 3: user-only, tell the user to type `/<skill>`. 4: has hooks, needs Claude; say so, do not read it.
- Plugin skills (`legal:*`, `anthropic-skills:*`) always use the Skill tool.

If a skill hands off to another in its own instructions, follow that. The skill knows its neighbors better than this router does.

## When the user asks what exists

For "what can you do" or "what skills are there", list the nine domains with one line each and ask what they are working on. Do not print the whole catalog.

## Keeping the map honest

`scripts/check-routes.sh` fails when a skill folder is missing from the domain files or a domain file names a skill that does not exist. It also lists user-only and hooks skills. Run it after adding or removing a skill.
