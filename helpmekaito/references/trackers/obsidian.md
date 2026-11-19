# Obsidian

Read with [task-writing.md](../task-writing.md). In Obsidian the notes are the tasks: one note per task in `<memory>/tasks/<slug>/`, written only through `kaito-tasks.sh`.

## Structure

| Part | Use it for |
|---|---|
| Note | One task. The file name is the id plus the title. |
| Properties | The YAML at the top: `id`, `title`, `status` (`todo`, `doing`, `done`), `due`, `created`, `updated`. |
| Task list | `- [ ]` lines under `### Items`: the steps. |
| Quote lines | Dated comments, newest last. |
| Links | `Link:` lines for a PR or doc; `[[wikilinks]]` to related notes. |
| `archive/` | Where done tasks go. |
| `index.md` | A generated list of open tasks. Never edit it. |

- A personal tracker often holds less than a team board. Write what the tracker's `note` says the user keeps there, usually one task with a link to the official ticket, not a copy of every sub-ticket.
- Big work is one note with items. Make a second note only for a part the user wants to track on its own, and link the two.

## Formats

- The body is Markdown. Property values are plain text: Markdown does not render there, and a link in a property must be quoted (`"[[Note]]"`).
- A property name has one type across the whole vault, so keep to the properties above and do not add new ones.
- File names avoid `# | ^ : %% [[ ]]`; the script makes the name from the title.
- Tags, if the user uses them: letters, numbers, `_`, `-`, `/`, no spaces, not numbers only.

## Fields

- `due` only when the user gave a date. There is no priority or assignee; do not invent properties for them.
- Status moves `todo`, `doing`, `done`. `done` moves the note to `archive/`.

## Recommendations to offer, once, as a question

- Tasks kept as loose checkboxes across many notes: one note per task, so each has a status and a history.
- A vault with Bases turned on: a base over the tasks folder gives a table or board view of these notes with no extra plugin.
- The same task tracked here and on a team board in full: keep the full ticket on the board and a one-line entry with its link here.

## Limits worth knowing

- Obsidian has no bulk edit for properties; changes go through the script.
- When the memory folder is outside the vault, notes reach Obsidian by the mirror and edits made in Obsidian are not read back.

Sources: obsidian.md/help (properties, tags, links, syntax, bases, plugins/templates).
