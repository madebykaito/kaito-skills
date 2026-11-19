# Trello

Read with [task-writing.md](../task-writing.md). This file holds what is particular to Trello.

## Structure

| Level | Use it for |
|---|---|
| Board | One project, team or workflow. |
| List | A stage the work passes through, left to right. Not a category. |
| Card | One deliverable: the smallest unit that moves across lists. |
| Checklist | The steps inside a card. On paid plans an item can have its own assignee and due date. |
| Label | A category that cuts across lists (type of work, area). Not a status: the list is the status. |
| Custom field | A structured value every card should carry (a reference, an estimate). |
| Template card | A reusable starting shape for a kind of card. |

- A step that needs its own owner, date or pull request becomes its own card, linked from the parent card. Otherwise it is a checklist line.
- A card that has grown too large to read is a sign to split it, or to give it its own board.

## Formats

- Description and comments take Trello's Markdown: bold, italic, headings, links, quotes, lists, inline and fenced code, dividers. Not full Markdown: no tables, no nested quotes.
- Checklist items render only bold, italic, strikethrough, inline code and links. Keep them to one plain line.
- Description, in order: goal, scope, done-when list, links. At most 16,384 characters.
- Follow the board's title pattern from `card_style` in `managers/trello.md` (a `[TAG]` prefix, a colon prefix).

## Fields

- New cards go to the To Do or Backlog list, finished ones to Done. A board with no Done list archives the card.
- Due and start dates, members, labels, custom fields: set only what the user gave. The script adds the user as a member of cards it creates when they are on the board.
- If the board has a reference-like custom field in use, fill it the way existing cards do. The script cannot set custom fields: use the Trello MCP.
- Links: `kaito-tasks.sh link <task> <url>` attaches the PR or doc to the card.

## Recommendations to offer, once, as a question

- No Done list: add one, so finished work stays visible instead of being archived.
- Lists that are categories rather than stages: labels for the categories, lists for the stages.
- A label used as a status ("blocked", "in review"): a list, or a checklist line that says what it waits on.
- Unclear list names or no incoming list: a "How this board works" card and an inbox list.
- The same steps in the description and a checklist: keep the checklist.

## Limits worth knowing

- About 300 requests per 10 seconds per key and 100 per token. Read a board with nested resources in one call, as `pull` does, not card by card.
- Board limits are large (about 5,000 open cards, 475 lists) but a board near them should be split.
- Butler automation runs are capped per month by plan. Do not create rules unasked.

Sources: trello.com/guide/trello-101, support.atlassian.com/trello (adding-checklists-to-cards, adding-labels-to-cards, using-custom-fields, creating-template-cards, how-to-format-your-text-in-trello, butler-quotas-and-limits), developer.atlassian.com/cloud/trello (object-definitions, limits, rate-limits), atlassian.com/blog/trello/trello-board-best-practices.
