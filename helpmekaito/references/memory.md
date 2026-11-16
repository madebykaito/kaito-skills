# Memory

Notes live in `~/.kaito/memory`: `MEMORY.md` (index), `global.md`, `projects/<slug>.md`. Read them with `kaito-mem.sh where`.

## Store

- Route corrections ("for this repo use X, not Y").
- Stack facts (framework, package manager, test runner).
- Verify commands (the exact build, test and lint commands).
- The codegraph decision (`kaito-mem.sh codegraph-decision yes|no`).

## Never store

- Secrets: keys, tokens, passwords. The script rejects them.
- Code or diffs.
- One-off task state or progress.

## Write

`~/.kaito/store/helpmekaito/scripts/kaito-mem.sh note global "<text>"` for facts true everywhere.
`~/.kaito/store/helpmekaito/scripts/kaito-mem.sh note project "<text>"` for facts about the current project.

One line per note. If it prints that memory is read-only, carry on, do not retry.

## Obsidian

If Obsidian MCP tools are in the session and `obsidian.enabled` is true in `~/.kaito/config.json`, also write the same note through MCP to `<obsidian.vault_path>/Memory.md`, `Global.md` or `projects/<slug>.md`. Otherwise the script's REST mirror handles it.
