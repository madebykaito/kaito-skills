# Learning

helpmekaito keeps what it learns about this user and this repo, and reads it back at the start of each task. `M=~/.kaito/store/helpmekaito/scripts/kaito-mem.sh`. Design: `docs/learning-loop.md` in the kaito-skills repo.

## Apply

`kaito-mem.sh where` prints `rule:` lines and up to ten `learn:` lines, most confirmed first. Follow them in the route, the skill choice, the model choice and the output, and pass the ones that matter to a skill or model you hand work to. A `rule:` is settled. A `learn:` yields to what the user says now.

## Capture

Capture as it happens, before your final answer. One line, written so it makes sense in a month with no other context.

| When | Command |
|---|---|
| The user corrects you: wrong route, wrong skill, wrong output, "no, do it this way" | `sh "$M" learn correction "<what to do instead>"` |
| The user states how they like things done | `sh "$M" learn preference "<text>"` |
| The user confirms an approach that was not the obvious one | `sh "$M" learn worked "<approach, and for what>"` |
| A route, skill, runner or model fails or gives a poor result | `sh "$M" learn failed "<what, and what to use instead>"` |
| You find a rule of this repo that is written nowhere | `sh "$M" learn convention "<text>"` |

- Add `global` as a last argument when it is about the user and true in every repo: `sh "$M" learn preference "<text>" global`. Everything else stays with the project.
- A `learn:` line shown by `where` that the user corrects you on again, or that proved right again: capture it again with the same text. That raises its count instead of adding a line.
- Count a correction every time it happens. It is the measure.

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
