# Tasks

helpmekaito keeps the user's tasks with their task manager and helps do them. `S=~/.kaito/store/helpmekaito/scripts` below.

## Onboarding

`./setup` runs this when it has a terminal. If `sh $S/kaito-tasks.sh status` shows `onboarding: pending`, finish the first step not yet done, in chat. Ask one question at a time. "skip" at any step sets `tasks.state` to `skipped`; stop asking.

1. **Manager.** "Where do you keep tasks: Trello, Obsidian, Asana, Jira, something else, or nowhere?" Then `node $S/kaito-json.mjs set ~/.kaito/config.json tasks.manager '"<trello|obsidian|asana|jira|other|none>"'` and `tasks.steps.manager true`.
2. **Memory folder.** Never ask for a vault path; read the vaults Obsidian knows from its `obsidian.json` (macOS `~/Library/Application Support/obsidian/`, Linux `~/.config/obsidian/`, Windows `%APPDATA%\obsidian\`).
   - Obsidian manager: no vault found means "Install Obsidian and create or open a vault first"; stop here. Otherwise list the vaults by number, let the user pick one, and offer `<vault>/kaito` as the memory folder.
   - Other managers: "Memory lives in `~/.kaito/memory`. Use another folder?"
   - On a path: set `memory.path`. If it is inside a known vault, set `obsidian.vault_root` to that vault. Set `tasks.steps.memory true`.
3. **Credentials.**
   - Trello: if `status` shows `credentials: no`, tell the user to run `sh ~/.kaito/store/helpmekaito/scripts/kaito-tasks.sh login` in their terminal. It explains how to get the key and token and stores them safely. Never ask for a key or token in chat, and never read `~/.kaito/.env`. Suggest the Trello connector too (Claude settings, Connectors, Trello) for reads the script does not cover.
   - Asana, Jira, others: check their MCP tools are in the session. If not, tell the user to add the connector and come back.
   - Obsidian, none: nothing to do.
4. **Discovery consent.** For Trello, run `kaito-tasks.sh boards` and show the board names as a numbered list, never the ids. Ask which to use: numbers, "all" or "none". Then ask:
   > Sync these boards' structure into local memory? That is lists, labels, custom fields and their options, members (id and username), every ID, and a short summary of how cards are written. No card contents are stored.

   Run `kaito-tasks.sh consent yes|no <boardId>...`, then `kaito-tasks.sh discover` on yes. Asana/Jira: same question; on yes, read the structure through the MCP and write `<memory>/managers/<name>.md` in the same shape as `trello.md`.
5. Set `tasks.state` to `done`.

## Per project

On a routed task in a repo where Trello is the manager:

- No `board:` line in `kaito-mem.sh where`: ask "Which board is this project on?" with names from `managers/<manager>.md`, then `kaito-tasks.sh map <boardId>`. "none" maps nothing; do not ask again in this repo (`kaito-mem.sh set board none`).
- A new board that is not in the consented list needs the consent question again.

Obsidian needs no mapping: each repo gets its own folder. Asana, Jira and others: ask which project or board once, and save it with `kaito-mem.sh set board "<manager> <id> <name>"`.

## Sync

- **Trello**: the board is the truth. Run `kaito-tasks.sh pull` at the start of a task route, then read from `<memory>/tasks/trello/<slug>/`. Those files are a cache: change tasks only through the script, which writes to Trello first. A `.conflict.md` copy means someone edited the cache; tell the user and apply what they want through the script.
- **Obsidian**: the notes in `<memory>/tasks/<slug>/` are the tasks. The script keeps ids and `index.md`.
- **Asana, Jira, others**: use their MCP for every read and write. Keep only the board map and the project's `board:` line locally.

## Commands

`kaito-tasks.sh list | add "<title>" [--list X] [--due ISO] | item add <task> "<text>" | check|uncheck <task> <item> | rename <task> "<title>" | move <task> <list> | comment <task> "<text>" | done <task> | reopen <task>`. Tasks and items are addressed by id, never by title. If a write prints `remote ok (<id>), local refresh failed`, do not repeat it; run `pull`.

## Helping do a task

1. `pull`, then read the task note: description, checklist, due date.
2. Route the work as usual (SKILL.md steps 1 to 5), with the task note as the brief.
3. Tick each checklist item with `check` as it finishes, not all at the end.
4. When the work is verified, `comment` with a one-line result (PR link, what changed). Move it to done only if the user says so or the checklist is complete.
5. New work found on the way becomes `item add` or `add`. Ask first if it is outside the task.

## Never

- Store secrets, card contents in notes, or anything from a board the user did not consent to.
- Set a due date or priority the user did not give.
- Delete cards. `done` moves or archives.
