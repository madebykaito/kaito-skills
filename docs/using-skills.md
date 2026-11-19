# Using the skills

A skill is a folder with a `SKILL.md`. It tells the agent how to do one job well: polish a layout, write a headline, review a diff. The agent loads it only when it is needed, so having many installed costs little.

## Three ways to use a skill

1. **Call it by name.** Type `/better-ui` or `/copywriting` in Claude Code, followed by what you want. Use this when you know the skill.
2. **Just ask.** Describe the task in plain words. The agent reads the skill descriptions and loads the one that fits.
3. **Ask the router.** Start with `/helpmekaito` and describe the goal. It picks one skill or a chain, says the route in one line, and runs it. Use this when you do not know which skill fits, or the goal needs several.

```text
/helpmekaito build a pricing page for a three-tier SaaS plan
```

```text
/better-typography fix the type scale on the settings page
```

```text
Review this diff and try to break it before I ship.
```

Claude Code lists most skills by name only, to keep its prompt small. They still load when called. `helpmekaito` and your hot list are listed in full, so the agent picks them on its own more often.

## What to ask for

| Domain | Try |
|---|---|
| Writing and copy | "Rewrite this hero headline, three options." "Remove the AI tone from this post." |
| Design and frontend | "Build a landing page from this brief." "Polish this dashboard." |
| Motion | "Find where animation would help on this page." "This modal transition janks, fix it." |
| Interface rules | "Check contrast and spacing on this screen." "Review this form's UI text." |
| Visual styles | "Give this card a glass look." "Add a progressive blur header." |
| Page types | "A pricing page with a FAQ." "A booking flow for a clinic." |
| SEO and marketing | "Audit this site's SEO." "Plan a set of comparison pages." |
| Video | "Make a 30-second product video from this site." "Add captions and a voiceover." |
| Media | "Generate a YouTube thumbnail for this title." (Needs a Higgsfield account.) |
| Engineering | "Plan this feature." "Debug this failing test." "QA the signup flow." "/ship" |
| Research | "Start a literature review on X." "Draft the methods section from my notes." |

## Chains

Some goals need several skills in order. `helpmekaito` knows these chains, called recipes:

| Goal | Chain |
|---|---|
| Landing page from a brief | `landing-page`, `copywriting`, `frontend-design`, `better-interface`, `schema`, gstack `/qa` |
| Polish an existing interface | `better-interface`, `impeccable`, `break-ui` |
| Motion pass | `remove-animations`, `find-animation-opportunities`, `improve-animations`, `animate` |
| Page that does not convert | `cro`, `copy-editing`, `analytics` |
| Product video | `stageshow`, `hyperframes`, `hyperframes-media`, `hyperframes-cli` |
| Research project | `brainstorming-research`, `writing-research-plan`, `literature-review`, `ingest-source`, `drafting-manuscript`, `requesting-peer-review` |
| Ship a change safely | `adversarial-review`, gstack `/qa`, then `/ship` |

Ask for the goal and the router runs the chain one step at a time. You can stop it after any step.

## The hot list

Skills on the hot list are listed in full for Claude Code and linked for Codex too. Put the few you use most there. Edit `~/.kaito/config.json`:

```json
{ "hot": ["better-ui", "copywriting", "systematic-debugging"] }
```

Then run `./setup` again.

## Codex

Codex gets `helpmekaito` plus your hot list. Ask for a skill by name and `helpmekaito` loads it from the store, even when it is not linked.

## Tasks and memory

`helpmekaito` can also keep a task list in sync with Trello, Plane or Obsidian, and remembers facts about each repo. Setup asks which task manager you use. Say "what are my tasks" or "add a task" to use it. Each repo can have its own tracker, or two (a team board and a personal one). The first time you plan work in a repo it asks once whether to track it there, and remembers the answer. Credentials stay in `~/.kaito/.env` and are never asked for in chat.
