# The learning loop

`helpmekaito` records what it learns while it works for you and reads it back at the start of the next task, so it works more the way you do in each repo. This is the first version.

Everything stays on your machine, in the memory folder (`~/.kaito/memory`, or `memory.path`). Nothing is sent anywhere or shared between users. If you turned on the Obsidian mirror, the project file and `global.md` are mirrored to your own vault like any other note.

## What is stored, and where

A learning is one line in a file that already exists:

```
learn: <kind> <count> <last confirmed> <text>
learn: correction 2 2026-11-20 use pnpm here, never npm
```

| Where | Holds |
|---|---|
| `projects/<slug>.md` | Learnings about one repo. The slug comes from the repo's `origin` remote, so checkouts and worktrees of one repo share the file. A repo with no network remote uses the folder name plus a hash of its path. |
| `global.md` | Learnings about you that hold in every repo (`learn ... global`). |
| `learning.log` | One line per capture: `<date> <project slug> <kind>`. Only `stats` reads it. |

Kinds: `correction` (you corrected the agent), `preference` (how you like things done), `worked` (an approach you confirmed), `failed` (a route, skill, runner or model that failed), `convention` (a repo rule that is written nowhere).

A promoted learning becomes a `rule: <text>` line in the same file. The files are plain text. You can read, edit or delete lines by hand.

## Capture

Every routed task ends with a durable-learning assessment. When it finds one eligible item, the agent sends it to `kaito-mem.sh capture <kind>` on standard input. The writer reports whether the canonical Markdown record was saved or already contains the normalized learning. The closeout reports failed persistence honestly. A task with no eligible item ends with `kaito-mem.sh closeout nothing_to_save`, which prints the word and writes nothing to memory.

A skipped closeout is reported at the next routed task. `where task` records each routed task's start in `~/.kaito/closeout/`, and `capture` or `kaito-mem.sh closeout nothing_to_save|skipped` closes it. If a task is still open when the next one starts, `where task` prints `closeout_missed:` and marks it missed. This is not a host hook. Tasks carry no id, so a miss can be a task still running, and closing a recovered lesson can hide a miss by that same task. Two starts at the same moment can lose one line.

Project scope is the default. Global scope requires the user to say that a correction or preference applies across projects. The writer does not store one-off task progress, secrets, code, diffs, or unverified deductions. `helpmekaito/references/learning.md` defines the exact capture rules.

`learn` remains for explicit or separately confirmed learning. Repeating it raises the count and date as before. Automatic closeout retries do not add another confirmation. `+`, `#` and a dot inside a word are kept in comparison, so `C++`, `C#` and `Node.js` stay apart.

If capture reports that memory is read-only, check write access from the running host. On a fresh Codex CLI session, `--add-dir` can grant access to the configured memory directory under the workspace-write sandbox. A busy writer releases its lock when it exits normally. After a force-quit or power loss, remove the `.lock` directory in the memory store only after confirming that no writer is active. The lock coordinates sessions on one machine.

Text that looks like a secret is refused: `token: x`, `password is x`, bearer tokens, common key prefixes (`sk-`, `ghp_`, `glpat-`, `AKIA`, `xox?-`), PEM blocks, JWTs, and any run of 32 or more characters that mixes letters and digits. That last rule also refuses a full commit hash. The check is a net, not a guarantee.

## Apply

`helpmekaito` already runs `kaito-mem.sh where` at the start of every routed task. It now prints, right after the board and local skill lines:

1. Every `rule:` line of the project and of `global.md`.
2. Up to ten `learn:` lines from the project and `global.md` together, most confirmed first, then most recent.
3. `learn_more: <n> not shown; run kaito-mem.sh curate` when there are more than ten.

These lines are always printed in full. Only what follows them (plain notes and the index) is cut to keep the output near 40 lines.

The agent uses them to pick the route, the skill and the model, and passes the relevant ones to work it hands off. A rule is settled. A learning yields to what you say now.

## Curate

`kaito-mem.sh curate` reports and changes nothing:

- `duplicate:` two learnings with the same text, or sharing at least 60% of their distinct words.
- `stale:` not confirmed for 30 days or more.
- `promote:` confirmed three times or more.

The agent runs it when `where` prints `learn_more:` or when you ask. It then acts with explicit commands, one learning at a time:

- `kaito-mem.sh forget "<text>" [global|project]` deletes one learning. Without the last word it looks in the project file first, then in `global.md`.
- `kaito-mem.sh promote "<text>" [global|project]` turns one learning into a `rule:` line, which is always printed and never goes stale.
- A learning that is a procedure of several steps can become a local skill in the repo's `.claude/skills/`. The agent asks first, writes the skill, and `kaito-project.sh record` lists it as a `local_skill:` line.

Nothing is deleted without one of these commands. A write that fails part way (a file that cannot be read, a failed rename) leaves the file as it was and logs nothing.

## Measure

`kaito-mem.sh stats` prints corrections captured per week for the last four weeks, oldest first, one row per project:

```
corrections per week, oldest first; the last week ends 2026-11-20
kaito-skills-1a2b3c4d: 4 3 1 0
closeouts not recorded: 1 of 6 routed tasks started in the last 28 days
```

The last line is for the current project: how many routed tasks started in the last 28 days have no recorded closeout. A falling row means you correct the agent less. A repeated correction counts each time, because the log keeps every capture, also for learnings that were later forgotten or promoted. A correction stored with `global` counts for the project it happened in.

## Left for later

- No check that a shown learning was actually used, and no count of tasks, so corrections are not yet a rate per task.
- Only the top ten by count and date are loaded. They are not matched to the task at hand.
- Duplicate detection is word overlap. It misses the same idea in different words and does not see two learnings that contradict each other.
- `curate` runs when the agent is told to. It is not scheduled, and merging is `forget` on one of the pair, with no command that adds the counts.
- Promotion writes a `rule:` line. Writing a rule into the repo's own `AGENTS.md` or `CLAUDE.md`, and drafting the local skill, are left to the agent and you.
- `learning.log` grows by one short line per capture and is never trimmed or mirrored to Obsidian.
- No per-skill or per-model figures (which route gets corrected most), and no way to export or share learnings with a team.
