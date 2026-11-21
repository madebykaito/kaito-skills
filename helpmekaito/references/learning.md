# Learning

helpmekaito keeps what it learns about this user and this repo, and reads it back at the start of each task. `M=~/.kaito/store/helpmekaito/scripts/kaito-mem.sh`. Design: `docs/learning-loop.md` in the kaito-skills repo.

## Apply

`kaito-mem.sh where` prints `rule:` lines and up to ten `learn:` lines, most confirmed first. Follow them in the route, the skill choice, the model choice and the output, and pass the ones that matter to a skill or model you hand work to. A `rule:` is settled. A `learn:` yields to what the user says now.

## Capture

At the closeout of every routed task, assess whether the completed work produced a durable learning. One eligible learning is captured at a time, written so it makes sense in a month with no other context.

| When | Command |
|---|---|
| The user corrects you: wrong route, wrong skill, wrong output, "no, do it this way" | `printf '%s' "<what to do instead>" | sh "$M" capture correction` |
| The user states how they like things done for this project | `printf '%s' "<text>" | sh "$M" capture preference` |
| The user confirms an approach that was not the obvious one | `printf '%s' "<approach, and for what>" | sh "$M" capture worked` |
| A route, skill, runner or model fails or gives a poor result | `printf '%s' "<what, and what to use instead>" | sh "$M" capture failed` |
| You find a rule of this repo that is written nowhere | `printf '%s' "<text>" | sh "$M" capture convention` |

- Add `global` only when the user explicitly says the preference or correction applies in every project: `printf '%s' "<text>" | sh "$M" capture preference global`. Everything else stays with the project.
- `capture` reports `saved`, `already_present`, or a failure. `saved` means the canonical Markdown record committed. `already_present` means the normalized learning is already in the selected scope, so automatic capture does not raise its count. A failure means nothing may be represented as saved. `nothing_to_save` is the closeout result when the assessment finds no eligible learning, not a writer result.
- Explicit `learn` remains available when the user asks to record or confirm a learning. Repeating that command raises the existing count and date. Automatic closeout records an identical learning only once.

## Closeout result

Complete the assessment even when there is nothing to save. Keep `nothing_to_save` quiet in the final answer. Say when memory is blocked and give the operational reason the writer returned. A user instruction not to retain a learning is `skipped`, with no writer call. The closeout does not create global memory unless the user made its cross-project scope explicit.

## Do not capture

- Secrets, keys, tokens, or text that holds one. The script refuses the common shapes; do not rely on it.
- One-off task state, progress, or anything true only for this task.
- What the repo already records: `AGENTS.md`, `CLAUDE.md`, the README, the brief ([project.md](project.md)).
- Code, diffs, or a guess the user has not confirmed.

## Curate

Run `sh "$M" curate` when `where` prints `learn_more:`, or when the user asks what you have learned or asks to clean it up. It only reports. For each line it prints, act with the learning's text:

- `duplicate: A || B`: keep the clearer one, `sh "$M" forget "<text of the other>"`.
- `stale:` (not confirmed for 30 days): if it is still true, capture it again; if not, `sh "$M" forget "<text>"`.
- `promote:` (confirmed three times): `sh "$M" promote "<text>"` turns it into a `rule:` line, which `where` always prints. If it is a procedure of several steps, ask the user whether to save it as a local skill in `.claude/skills/<name>/SKILL.md`; on a yes write it, run `kaito-project.sh record` ([project.md](project.md)) and `forget` the learning.

`forget` and `promote` look in the project file first, then in `global.md`. When the same text is in both, add `global` or `project` as a last argument to pick one: `sh "$M" forget "<text>" global`.

Never edit or delete a learning any other way, and never forget one the report did not name unless the user asks.

## Measure

`sh "$M" stats` prints corrections per week for the last four weeks, one row per project. Fewer is better. Show it when the user asks whether this is working.
