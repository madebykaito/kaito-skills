# Memory

Notes live in the memory folder: `sh ~/.kaito/store/helpmekaito/scripts/kaito-mem.sh dir` prints it (`memory.path` in `~/.kaito/config.json`, default `~/.kaito/memory`). It holds `MEMORY.md` (index), `global.md`, `projects/<slug>.md`, `managers/` (board maps: `trello.json`, `plane.json` and a readable `.md` of each) and `tasks/` (see [tasks.md](tasks.md)) and `learning.log` (one line per captured learning). Read notes with `kaito-mem.sh where`.

Notes are facts you looked up. What the user or the work taught you (corrections, preferences, what worked or failed, unwritten conventions) is a learning: capture it with `kaito-mem.sh learn`, not `note` ([learning.md](learning.md)).

## Project file

Project facts live in `projects/<slug>.md`. `kaito-mem.sh slug` prints the project's memory slug. It comes from the repo's `origin` remote, not the checkout path. The remote is reduced to host and path: credentials, port, query and fragment are dropped, a trailing `/` and `.git` are removed, and the host is lower-cased. An SSH host alias is resolved to its real host (`ssh -G`). The slug is the repo name followed by 8 hex characters of a hash of that remote. Checkouts and worktrees of one repo share the file. A repo with no network remote (no remote, a local path or `file://`) keeps the old slug: the folder name plus a hash of its path.

The task folders under `tasks/` and the codegraph index use the checkout slug (`kaito-codegraph.sh slug`), not the project slug.

Old per-checkout project files are merged into the repo's file the first time a command uses it, and the old file moves to `projects/.migrated/`. If the merge cannot run (read-only memory, busy lock), reads still include the old file and the merge happens on a later run. A file the automatic step cannot reach (for example one from another machine's path) is merged by hand:
`sh ~/.kaito/store/helpmekaito/scripts/kaito-mem.sh merge <old-slug>`
where `<old-slug>` is the file name under `projects/` without `.md`. It must be a single name, and it must not be the current project's file.

## Owner memory

Business work for one owner (a brand the user runs, see the `business` skill) adds that owner's memory. Pass `--owner <id>`, the id `kaito-owner.mjs resolve` printed:

- `kaito-mem.sh where task --owner <id>` prints the usual lines plus `owner=`, `owner_file=` and that owner's `owner.md`: `rule:` lines, learnings and facts. Owner facts come first in the facts section. No other owner's file is read.
- `kaito-mem.sh capture <kind> --owner <id>`, `learn <kind> "<text>" --owner <id>` and `note owner "<text>" --owner <id>` write to the owner's file only. `global` with `--owner` is refused.
- `forget|promote "<text>" owner --owner <id>` changes the owner's file only.
- `note global|project` with `--owner` is refused: those files are read in every other owner's tasks.

Owner captures are logged in the owner's own `learning.log`, not the shared one. A linked `owner.md` or memory folder is refused.

The owner's file is `owner.md` in its `memory_root`, or in `~/.kaito/owners/<id>/memory/`. It is not indexed in `MEMORY.md` and not mirrored to Obsidian; point `memory_root` into the vault instead. Without `--owner` no owner memory is read or written, and repo memory works as before.

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
