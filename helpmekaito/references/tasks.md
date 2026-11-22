# Tasks

helpmekaito keeps the user's tasks with their task manager and helps do them. `S=~/.kaito/store/helpmekaito/scripts` below.

## Onboarding

`./setup` runs this when it has a terminal. If `sh $S/kaito-tasks.sh status` shows `onboarding: pending`, finish the first step not yet done, in chat. Ask one question at a time. "skip" at any step sets `tasks.state` to `skipped`; stop asking.

1. **Manager.** "Where do you keep tasks: Trello, Plane, Linear, Obsidian, Asana, Jira, something else, or nowhere?" Then `node $S/kaito-json.mjs set ~/.kaito/config.json tasks.manager '"<trello|plane|linear|obsidian|asana|jira|other|none>"'` and `tasks.steps.manager true`.
2. **Memory folder.** Never ask for a vault path; read the vaults Obsidian knows from its `obsidian.json` (macOS `~/Library/Application Support/obsidian/`, Linux `~/.config/obsidian/`, Windows `%APPDATA%\obsidian\`).
   - Obsidian manager: no vault found means "Install Obsidian and create or open a vault first"; stop here. Otherwise list the vaults by number, let the user pick one, and offer `<vault>/kaito` as the memory folder.
   - Other managers: "Memory lives in `~/.kaito/memory`. Use another folder?"
   - On a path: set `memory.path`. If it is inside a known vault, set `obsidian.vault_root` to that vault. Set `tasks.steps.memory true`.
3. **Credentials.**
   - Trello: if `status` shows `credentials: no`, tell the user to run `sh ~/.kaito/store/helpmekaito/scripts/kaito-tasks.sh login` in their terminal. It explains how to get the key and token and stores them safely. Never ask for a key or token in chat, and never read `~/.kaito/.env`. Suggest the Trello connector too (Claude settings, Connectors, Trello) for reads the script does not cover.
   - Plane: same `login` command; it asks for the workspace slug and a personal API key (and the URL of a self-hosted Plane). The same rule holds: never ask for the key in chat. If the user will not make a key and the Plane MCP tools are in the session, use the MCP path below and set `tasks.steps.credentials true`.
   - Linear: same `login` command; it asks for a personal API key (Linear, Settings, Security & access, Personal API keys). One key covers the whole workspace. A `LINEAR_API_KEY` already in `~/.config/linear/.env` is used too. The same rule holds: never ask for the key in chat. If the user will not make a key and the Linear MCP tools are in the session, use the MCP path below and set `tasks.steps.credentials true`.
   - Asana, Jira, others: check their MCP tools are in the session. If not, tell the user to add the connector and come back.
   - Obsidian, none: nothing to do.
4. **Discovery consent.** For Trello, Plane and Linear, run `kaito-tasks.sh boards` and show the board (Plane: project, Linear: team) names as a numbered list, never the ids. Ask which to use: numbers, "all" or "none". Then ask:
   > Sync these boards' structure into local memory? That is lists, labels, custom fields and their options, members (id and username), every ID, and a short summary of how cards are written. No card contents are stored.

   For Plane the structure is states, modules, labels, members (id and name), every ID and a summary of how work items are written; no work item contents.

   For Linear the structure is states, projects, labels, members (id and name), every ID and a summary of how issues are written; no issue contents.

   Run `kaito-tasks.sh consent yes|no <boardId>...`, then `kaito-tasks.sh discover` on yes. Asana/Jira: same question; on yes, read the structure through the MCP and write `<memory>/managers/<name>.md` in the same shape as `trello.md`.
5. Set `tasks.state` to `done`.

## Per project

A project is tracked in the tool its owner chose for it, and one project can have more than one tracker (an official team board and a personal one, each a different tool). They are lines in the project's memory file, shown first by `kaito-mem.sh where`:

`tracker: <manager> <id> <name> | role=<official|personal> | tracking=<always|never|ask> | note=<what goes here>`

- `kaito-tasks.sh tracker list | add <manager> <id> [name] [role=] [tracking=] [note=] | set <manager> key=value | rm <manager>`. `map <boardId>` is the short form for one Trello or Plane tracker, and `map <teamId>[/<projectId>]` for Linear; it looks the name up. To add a tracker the machine's default manager is not, name it first: `kaito-tasks.sh --tracker linear login`, then `--tracker linear boards`, then `--tracker linear map <teamId>[/<projectId>]`. `kaito-tasks.sh projects <teamId>` lists a Linear team's open projects.
- An older `board:` line is one official tracker with `tracking=ask`. `tracking: never` (or the old `board: none`) means the project is not tracked anywhere: do not read, write or ask.
- A command acts on one tracker: `--tracker <manager>` names it, otherwise the first scripted one (Trello, Plane, Linear, Obsidian). `list` shows every scripted tracker under its own heading. Asana, Jira and others keep the same line and go through their MCP.
- Role and note come from what the user says ("Jira is the team board, the Obsidian notes are just mine"). Never infer a role. If it matters for a write and was not said, ask.

### First use in a project

No `tracker:`, `board:` or `tracking:` line means this project has not been set up. Do it then, in the same conversation, before the first task read or write:

1. Run `kaito-tasks.sh detect`. It reads local evidence only and prints `candidate: <manager> <id> <name> | strength=<strong|weak> | evidence=<what was seen>`, then `known: <managers with a stored structure>`.
2. One strong candidate: propose it with its evidence in one line and ask. "This repo's branch carries the key ALL, so it looks like Plane project ALL. Track it there?"
3. Several candidates, or only weak ones: list them by name and ask which, allowing more than one and "none".
4. `candidate: none`: ask which tool tracks this project, or none. Offer the names in `managers/<manager>.md` if there are any.
5. On a yes: `tracker add` (or `map`), then ask the tracking question below. On "none": `kaito-tasks.sh tracking never`.

Do not guess. Never add a tracker without a yes, never pick between two candidates yourself, and never treat weak evidence as an answer. A board outside the consented list needs the discovery consent question first.

### Tracking: asked once, then remembered

When the user plans work in a project ("let's implement X and Y"), look at the tracker's `tracking`:

- `ask`: ask once. "Track this in <name>? Always for this project, just this once, or never." Save the answer with `tracker set <manager> tracking=always|never`; "just this once" saves nothing.
- `always`: draft the tickets (see below), show them once, create them on yes. From then on keep them current without asking: tick items as they finish, move the state when work starts, comment the result with its link.
- `never`: do the work and leave the tracker alone. The script refuses reads and writes; do not work around it with the MCP. Do not bring tracking up at all: no question, no offer, no reminder of how to turn it on. The user changes it by asking.
- The user can change it at any time ("always track this project", "stop tracking here"): `tracker set`.
- Even under `always`, ask before: moving a parent to done while sub-items are open, tracking work outside what was planned, creating a label, module, state or list, and opening a GitHub issue.

With two trackers each has its own setting. Write to every tracker set to `always`, shaped by its role and note: the full tickets on the official one, what the user said they keep on the personal one. Put a link to the official ticket in the personal entry. Do not copy tickets between tools beyond that.

### Planned work becomes tickets

1. Read [task-writing.md](task-writing.md) and `trackers/<manager>.md`.
2. One parent ticket for the piece of work, with a sub-ticket per independently shippable part and checklist lines for the steps inside a part. Small work is one ticket.
3. Put them under what already exists (the mapped module, the right list or epic). Check the cache first so nothing is created twice.
4. Show the whole draft once, then create with `add`, `item add` and, where the script has no command, the tool's MCP.
5. Big work in a repo on GitHub may also get one linked issue: follow [github-issues.md](github-issues.md), which always asks first.

## Sync

The task folders below are named from the checkout slug (the path of this checkout). The project's tracker lines are in the project file, which every checkout of the repo shares. Each checkout keeps its own task cache. A Linear cache is cleared when the project's Linear mapping has changed since it was pulled, so it is never trusted under an older mapping.

- **Trello**: the board is the truth. Run `kaito-tasks.sh pull` at the start of a task route, then read from `<memory>/tasks/trello/<checkout slug>/`. Those files are a cache: change tasks only through the script, which writes to Trello first. A `.conflict.md` copy means someone edited the cache; tell the user and apply what they want through the script.
- **Plane**: the project (or the mapped module) is the truth, cached in `<memory>/tasks/plane/<checkout slug>/`. A list is a state, a task id is the work item key (`ALL-27`), and a checklist item is a sub work item: `item add` creates one under the task, `check` moves it to the completed state. `add` on a mapped module puts the new item in that module.
- **Linear**: the team (or the mapped project) is the truth, cached in `<memory>/tasks/linear/<checkout slug>/`. A list is a workflow state; to-do is the first `unstarted` state (else backlog), done the first `completed` state, and completed, canceled and duplicate count as closed. A task id is the issue identifier (`KAI-27`), and a checklist item is a sub-issue: `item add` creates one, `check` moves it to the completed state. `add` on a mapped project puts the new issue in that project. `pull` reads only open issues.
- **Structure memory** (`managers/trello.json`, `managers/plane.json`, `managers/linear.json` and their `.md`): `pull` refreshes it by itself when it is older than `tasks.structure_ttl_hours` (default 24), and a write that meets an unknown Plane or Linear state reads the states again. Run `discover` by hand only after adding a board to the consent list.
- **Obsidian**: the notes in `<memory>/tasks/<checkout slug>/` are the tasks. The script keeps ids and `index.md`.
- **Asana, Jira, others**: use their MCP for every read and write. Keep only the board map and the project's `tracker:` line locally (`kaito-tasks.sh tracker add <manager> <id> "<name>"`).

## Plane through the MCP

`kaito-tasks.sh status` showing `credentials: no` with the Plane MCP tools in the session means the MCP path. Use the MCP for every read and write, with the same rules as the script: to-do is the first `unstarted` state, done is the first `completed` state, a checklist item is a sub work item, new items go into the mapped module. After reading a project's structure, store it with `kaito-tasks.sh structure put plane` (JSON on stdin: `{"workspace","me":{"id","display_name"},"boards":{"<projectId>":{"name","identifier","states":[{"id","name","group"}],"modules":[{"id","name"}],"labels":[{"id","name"}],"members":[{"id","display_name"}]}}}`), and save the project's line with `kaito-tasks.sh tracker add plane <projectId>[/<moduleId>] "<name>"`. Use the MCP also when there is a key but the script has no command for the job: pages, cycles, epics, relations.

## Linear through the MCP

`kaito-tasks.sh status` showing `credentials: no` with the Linear MCP tools in the session means the MCP path. Use the MCP for every read and write, with the same rules as the script: to-do is the first `unstarted` state (else backlog), done is the first `completed` state, a checklist item is a sub-issue, new issues go into the mapped project. After reading a team's structure, store it with `kaito-tasks.sh structure put linear` (JSON on stdin: `{"workspace","me":{"id","display_name"},"boards":{"<teamId>":{"name","identifier","states":[{"id","name","group"}],"modules":[{"id","name"}],"labels":[{"id","name"}],"members":[{"id","display_name"}]}}}`; `identifier` is the team key, `modules` are the team's projects), and save the line with `kaito-tasks.sh tracker add linear <teamId>[/<projectId>] "<name>"`. Use the MCP also when there is a key but the script has no command for the job: cycles, initiatives, relations, documents, triage, milestones.

## Commands

`kaito-tasks.sh list | add "<title>" [--list X] [--due ISO] | item add <task> "<text>" | check|uncheck <task> <item> | rename <task> "<title>" | move <task> <list> | comment <task> "<text>" | link <task> <url> ["<title>"] | done <task> | reopen <task>`. Tasks and items are addressed by id, never by title. If a write prints `remote ok (<id>), local refresh failed`, do not repeat it; run `pull`.

## Helping do a task

1. `pull`, then read the task note: description, checklist, due date. If something in it would trip up the next reader, offer one fix as a question ([task-writing.md](task-writing.md), last section).
2. Route the work as usual (SKILL.md steps 1 to 5), with the task note as the brief.
3. Tick each checklist item with `check` as it finishes, not all at the end.
4. When the work is verified, `comment` with a one-line result (PR link, what changed). Move it to done only if the user says so or the checklist is complete.
5. New work found on the way becomes `item add` or `add`. Ask first if it is outside the task.
6. Everything written follows [task-writing.md](task-writing.md) and the tool's file in `trackers/`.

## Never

- Store secrets, card contents in notes, or anything from a board the user did not consent to.
- Set a due date or priority the user did not give.
- Map a tracker, or write to one, that the user has not confirmed for this project.
- Write to a tracker whose `tracking` is `never`, by any route.
- Delete cards or work items. `done` moves or archives.
