# Project context

helpmekaito learns each repo once and refreshes when it changes. `S=~/.kaito/store/helpmekaito/scripts`.

## When

On a routed task in a git repo, run `sh $S/kaito-project.sh changed`.

- `new` or `changed`: run `sh $S/kaito-project.sh scan`, write the brief, then `sh $S/kaito-project.sh record`.
- `same`: use the project file as it is.

## The brief

Up to ten `kaito-mem.sh note project` lines, only what the scan and a quick read of the instruction files show:

- Stack and package manager.
- The exact build, test and lint commands.
- Where the code lives (top folders and what they hold). With `indexed=yes`, take this from `codegraph_explore`.
- Rules from `AGENTS.md`, `CLAUDE.md` or similar that change how to work here.

Replace a stale line rather than adding a second one. Architecture beyond that is read per task, not stored.

## Local skills

`record` writes one `local_skill: <name> <path> <description>` line per skill in `.claude/skills/` and `.agents/skills/`.

- In routing, a local skill that fits the request beats a store skill, and beats a store skill of the same name.
- A skill the user names still wins.
- Claude: the repo's `.claude/skills` are already in the session; invoke by name through the Skill tool.
- Codex and other hosts: the `local_skill:` path is relative to the repo root. Read that file and follow it, resolving its own relative paths against its folder.
- A path that no longer exists is dropped on the next `record`.
