# Upgrade, version, uninstall

helpmekaito keeps kaito-skills current and can remove it. `K=~/.kaito/store/helpmekaito/scripts/kaito-self.sh` below. `KAITO_HOME` replaces `~/.kaito` here as elsewhere.

## What `auto` printed

`sh $K auto` runs at the start of a routed task. It looks for a newer release at most once a day, never prompts and never fails. Whatever it printed, the user's task still gets done.

- Nothing: go on. Do not mention updates.
- `upgrading kaito-skills A -> B in the background`: say so in one short line and continue the task. The upgrade never holds up the task; a later task start prints how it went.
- `upgraded: A -> B`, then changelog lines and `new sessions use the new skills`: the first line of your final answer says it, whatever else the answer holds: one or two sentences (the two versions, the top changes, and that this session keeps the old skills until a new one starts). Do not ask anything. Then continue the task.
- `upgrade skipped: <reason>` and `to upgrade by hand: ...`: say why in one line and give that command. Do not try to fix the clone yourself. Then continue the task.
- `update: A -> B` alone (the user chose to be asked): ask one question. "kaito-skills B is out, you have A. Upgrade now, later, or stop checking?"
  - now: `sh $K upgrade`, relay the result as above.
  - later: `sh $K snooze`. It stays quiet about B for 7 days.
  - stop checking: `sh $K mode off`.

  Name the route for the task in the same reply, and continue it whatever the answer is. Never say it was upgraded before `upgrade` printed `upgraded:`.

## When the user asks

These skip routing.

- "upgrade kaito", "update kaito skills", `/helpmekaito upgrade`: `sh $K upgrade`. `up to date: A` means there is nothing newer. It installs releases only, never unreleased work, and it changes no setting or earlier answer.
- "what version of kaito", `/helpmekaito version`: `sh $K version`. To also see whether a newer one exists: `sh $K check --force` (`update: A -> B`, or nothing).
- "stop upgrading by yourself", "ask me first": `sh $K mode ask`. "turn updates off": `sh $K mode off`. "turn them back on": `sh $K mode auto`. Each prints `updates: <mode>`; say it back in one line.

## Uninstall

"uninstall kaito", "kaito, uninstall yourself", `/helpmekaito uninstall`:

1. Run `sh $K uninstall` with no flags. It is a dry run and removes nothing. Show its `would remove:`, `would restore:` and `keeps:` lines.
2. Ask once: "Remove these?"
3. Only on a yes: `sh $K uninstall --yes`.
4. Say that this session still has the old skills loaded and a new session will not, and that the kaito-skills clone and `~/.kaito` (config, memory, task credentials) are still there.

`--purge` also deletes `~/.kaito`. "Uninstall" never means purge: on a plain uninstall request do not mention `--purge` at all, not even as an option for later. Bring it up only when the user asks to remove everything or their data. Name what is lost (config, memory, task credentials) and get a separate, explicit yes for it. Then `sh $K uninstall --yes --purge`.

Never run or suggest `./setup --uninstall` or `./setup --purge`: they do not preview and do not ask. No shell in this session: give the user the two `kaito-self.sh` commands to run, dry run first.

## Same-name skills and plugins

`./setup` asks, in the terminal, whether to replace skills the user already has under a kaito skill's name and whether to disable Claude Code plugins that ship one. helpmekaito never does either itself: no moving skills aside, no editing `enabledPlugins`. If the user wants it, tell them to run `./setup` in their kaito-skills clone and answer there (`./setup --duplicates` asks again about ones they said no to). Uninstall puts both back.
