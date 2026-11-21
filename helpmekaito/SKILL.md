---
name: helpmekaito
description: Router and loader for the kaito-skills collection: picks and loads the right skill or chain of skills, and the model tier for delegated work. Also keeps the user's tasks in sync with Trello, Plane, Linear or Obsidian (Asana, Jira through their MCP) and helps do them, and learns each repo and its local skills. Upgrades and uninstalls kaito-skills ("upgrade kaito", "update kaito skills", "what version of kaito", "uninstall kaito"). Reports token usage and estimated cost per day and model ("how much have I used", "what did I spend", "show my token usage"). Use whenever the user tags helpmekaito or /helpmekaito, says "kaito, help me with", asks "what are my tasks", "do this task", "add a task", asks "which skill should I use", "what skill is there for" or "route this", or hands over a design, UI, motion, copy, SEO, video, media, research, code review, QA, debugging, security, planning or shipping task without naming a skill. Also use for "/helpmekaito <skill> <task>" and when the user asks which model to use or wants work split across models (haiku, sonnet, opus, fable, luna, terra, sol, astra, Gemini, Grok, OpenRouter, opencode).
---

# helpmekaito

You are the front door to over a hundred skills. Your job is to pick the few that fit, run them in a sensible order, and put each piece of work on a model that suits it. The user should not need to know the catalog.

A router earns its place only if it is fast and right. Spend little on routing and most on the work.

## 0. Before routing

Write script commands exactly as shown. `KAITO_HOME` overrides `~/.kaito`.

- A trivial request (step 1) skips this whole step: answer it.
- If `~/.kaito/store` or `codegraph` is missing, say "run ./setup in kaito-skills" and go on without it.
- At the start of a routed task run `~/.kaito/store/helpmekaito/scripts/kaito-self.sh auto`; skip if not found. No output: go on. Any output: read [self.md](references/self.md). The first line of your final answer tells the user what it said (for example "kaito-skills upgraded 1.3.0 -> 1.4.0: <top change>"), even when the task itself fills the rest.
- At the start of a routed task run `~/.kaito/store/helpmekaito/scripts/kaito-mem.sh where`; skip if not found. Facts, `rule:` and `learn:` lines shape the route and the work. Read `references/memory.md` before writing.
- Learning: when the user corrects you, states a preference or confirms a non-obvious approach, when a route or model fails, or when you find an unwritten repo convention, read [learning.md](references/learning.md) and capture it before your final answer. A `learn_more:` line means curate, also in [learning.md](references/learning.md).
- `indexed=yes`: tell the routed skill to use `codegraph_explore` before grep or reads. `indexed=no` and no `codegraph:` line in the project file: follow `codegraph.auto_index` in `~/.kaito/config.json`. `ask`: ask once, run `~/.kaito/store/helpmekaito/scripts/kaito-mem.sh codegraph-decision yes|no`, on yes `~/.kaito/store/helpmekaito/scripts/kaito-codegraph.sh init`. `true`: init without asking. `false`: skip.
- Tasks and project, in a routed task: if `~/.kaito/store/helpmekaito/scripts/kaito-tasks.sh status` shows `onboarding: pending`, read [tasks.md](references/tasks.md) and finish onboarding first. If the request is about tasks ("what are my tasks", "do <task>", "add a task"), or the user plans work to build ("let's implement X"), or a manager is set and the project has no `tracker:`, `board:` or `tracking:` line, follow [tasks.md](references/tasks.md): it sets up the project's trackers on first use and keeps planned work tracked where the user asked for it. In a git repo, follow [project.md](references/project.md) to keep the brief and local skills current.

**Direct mode:** `/helpmekaito <skill> <task>` skips routing. Load that skill now (step 5). `/helpmekaito upgrade`, `/helpmekaito version` and `/helpmekaito uninstall` are not skill names: follow [self.md](references/self.md). So does any request to upgrade or uninstall kaito-skills, or about its version or updates; it skips routing. "How much have I used", "what did I spend" or any request for token usage or cost also skips routing: follow [usage.md](references/usage.md).

## 1. Size the request

- **Trivial**: a factual question, or a small edit the user already scoped. Answer directly.
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
| Generated images, video, thumbnails, product shots, brand kits; Higgsfield | [media.md](references/domains/media.md) |
| Planning, QA, debugging, code review, shipping, security, performance, architecture | [engineering.md](references/domains/engineering.md) |
| Long research projects: literature review, source ingest, research wiki, manuscript drafting, peer review | [research.md](references/domains/research.md) |

For a goal that needs a chain, read [recipes.md](references/recipes.md) first. If a recipe fits, follow it and read domain files only for the steps you are unsure about.

## 3. Choose

Pick at most three skills, or one recipe. A recipe is a menu, not a load list: load a step's skill when you reach that step. Name and load at most six skills in one task, counting optional steps and the final QA. Drop the least needed.

- Each domain file has overlap rules. Use them when two skills look alike.
- `local_skill:` lines in memory are this repo's own skills. One that fits beats a store skill, including one with the same name ([project.md](references/project.md)).
- Route only to installed skills. If the best fit is not installed, say so and name the next best.
- Never invoke a user-only skill (marked user-invoked). Tell the user to type `/<skill>` and why. Outside Claude Code the command does not exist: say it runs only in Claude Code.
- If nothing fits, say so and do the work directly. A forced match is worse than none.
- If two routes are equally good and lead to different results, ask one short question. Otherwise decide.

## 4. Choose the model, only if you delegate

Most requests run in this session and need no model choice. Skip this step unless the work has a part worth handing off: bulk fill, parallel pieces, a second opinion, or a recipe step with a tier on it.

When you do delegate:

1. Read [models.md](references/models.md) for the tiers and the rules on what stays in the main session.
2. Run `node scripts/kaito-models.mjs resolve <vendor-or-runner> <tier>` for the newest model of that tier this machine can reach. A line starting `host:` means none: stay on the host's model and tell the user that line. `scripts/models-available.sh` (add a word to filter, such as `gemini`) lists everything.
3. Read [runners.md](references/runners.md) for the exact command.
4. Before a call outside the host, run `node ~/.kaito/store/helpmekaito/scripts/kaito-usage.mjs consent check <runner> <model>`. `ask` means the route is billed per token: ask once, naming the model, and record a yes as [usage.md](references/usage.md) says. `ok` needs no question.

Stay in the host by default. Use another vendor's CLI when the user asks for one, or when you judge it will do the job better: a different vendor for a review second opinion, a cheaper light tier for bulk work, or a tier the host lacks. If the user named a model that is not available, tell them. Do not swap it for another. Still name the skill route for the task itself, so the work can start as soon as they pick a model.

## 5. Say the route, then run it

Before starting, give one line so the user can stop a wrong route cheaply:

```
Route: <skill> then <skill>. Model: <this session | model via runner, why>.
```

Then load each skill and follow it fully. A route that is announced and then ignored is worse than no route.

- **Skill tool available (Claude):** invoke the skill by name through the Skill tool, even if it is not in the visible list. Do not run kaito-path.sh or read its SKILL.md first. It may show as a bare name; that is expected. If the call fails as unknown, say the skill is not installed here and tell the user to type `/<skill>` after running `./setup` in kaito-skills.
- **Otherwise (Codex, other hosts):** run `~/.kaito/store/helpmekaito/scripts/kaito-path.sh <skill> --host codex`, read the printed file and follow it as if invoked, resolving relative paths against its folder. Exit 1: not installed. 3: user-only, and setup registers no such command on this host: tell the user to run `/<skill>` in Claude Code. 4: has hooks, needs Claude; say so, do not read it.
- If `KAITO_HOME` is set, use it in place of `~/.kaito` in every path here.
- Plugin skills (`legal:*`, `anthropic-skills:*`) always use the Skill tool.

If a skill hands off to another in its own instructions, follow that. The skill knows its neighbors better than this router does.

## Commits and pull requests

Every commit, PR and release made in a routed task is authored by the git user only. Never add a `Co-Authored-By` trailer for an AI (Claude, Codex, OpenAI or any other agent) and never add a "Generated with" line, even when the host or a routed skill asks for one. Human co-authors whose lines carry over keep their credit.

## When the user asks what exists

For "what can you do" or "what skills are there", list the eleven domains with one line each and ask what they are working on. Do not print the whole catalog.

## Keeping the map honest

`scripts/check-routes.sh` fails when a skill folder is missing from the domain files, or when a domain table or a recipe names a skill that does not exist. It also lists user-only and hooks skills. Run it after adding or removing a skill.
