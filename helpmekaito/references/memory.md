# Memory

Notes live in the memory folder: `sh ~/.kaito/store/helpmekaito/scripts/kaito-mem.sh dir` prints it (`memory.path` in `~/.kaito/config.json`, default `~/.kaito/memory`). It holds `MEMORY.md` (index), `global.md`, `projects/<slug>.md`, `managers/` (board maps: `trello.json`, `plane.json` and a readable `.md` of each) and `tasks/` (see [tasks.md](tasks.md)) and `learning.log` (one line per captured learning). Read notes with `kaito-mem.sh where`.

Notes are facts you looked up. What the user or the work taught you (corrections, preferences, what worked or failed, unwritten conventions) is a learning: capture it with `kaito-mem.sh learn`, not `note` ([learning.md](learning.md)).

## Store

- Stack facts (framework, package manager, test runner).
- Verify commands (the exact build, test and lint commands).
- The codegraph decision (`kaito-mem.sh codegraph-decision yes|no`).
- The project brief and local skills ([project.md](project.md)).

## Never store

- Secrets: keys, tokens, passwords. The script rejects the obvious shapes only, so do not rely on it.
- Code or diffs.
- One-off task state or progress in notes. Tasks live in `tasks/` through `kaito-tasks.sh`, never in notes.

## Write

`~/.kaito/store/helpmekaito/scripts/kaito-mem.sh note global "<text>"` for facts true everywhere.
`~/.kaito/store/helpmekaito/scripts/kaito-mem.sh note project "<text>"` for facts about the current project.
`kaito-mem.sh learn|forget|promote` for `learn:` and `rule:` lines ([learning.md](learning.md)).
`kaito-mem.sh set board|brief_fp "<value>"` for keyed project lines. A project's `tracker:` and `tracking:` lines are written only by `kaito-tasks.sh tracker` and `tracking` ([tasks.md](tasks.md)).

One line per note; line breaks are flattened. If it prints that memory is read-only, carry on, do not retry.

## Obsidian

The scripts mirror notes to Obsidian through its REST API when `obsidian.enabled` is true. Do not also write them through an Obsidian MCP. When the memory folder is inside the vault (`obsidian.vault_root`), there is nothing to mirror.
