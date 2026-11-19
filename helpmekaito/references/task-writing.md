# Writing tasks

Rules for anything helpmekaito writes to a tracker: tickets, sub-tickets, checklist items, comments, GitHub issues. They hold for every tool. The tool's own structure and formats are in `trackers/<tool>.md`; read that file too before the first write to a tool in a session. Where the board's own habits (`card_style` or `item_style` in `managers/<tool>.md`) differ from these rules, the board wins.

A ticket should read as if a careful teammate wrote it: the reader can act on it without asking what was meant, and nothing in it is there only to sound thorough.

## Title

- An action and its object: "Add Plane login to setup", not "Plane" and not "Working on the Plane integration".
- Specific enough to tell apart from its neighbours in a list. About 70 characters at most.
- No status, date, owner or priority in the title; those have fields.
- Follow the board's pattern if it has one (a prefix, a ticket key).

## Description

Write only the parts that apply, in this order:

1. **Goal.** One to three sentences: what will be true when this is done, and why it is wanted now.
2. **Scope.** What is in, and what is out if a reader could assume otherwise.
3. **Done when.** Acceptance criteria as a short list. Each one can be checked by running something or looking at something: a command that passes, a screen that shows X, a file that exists.
4. **Links.** PR, branch, design doc, parent ticket, related tickets. Links only, no pasted content.

Leave out: the conversation that led to the ticket, restated context the linked doc already holds, implementation steps (those are the checklist), and anything you would write only to fill a heading. A small task can be a title and one line.

## Steps

- Steps go in the checklist or as sub-tickets, never in the description as well.
- A checklist line is one concrete action, small enough to tick in one sitting.
- Make a sub-ticket only when the step can be assigned, scheduled or shipped on its own (a rule of thumb: it gets its own pull request). Otherwise it is a checklist line.
- Big work is one parent ticket with sub-tickets, not a flat pile of siblings.

## A ticket an agent can pick up

Work is often handed to a coding agent, so each ticket that may be picked up stands alone:

- The goal in one sentence, and the exact scope.
- Where the work is: repo, folder or files, if known.
- Done-when criteria a command or test can check, and the command.
- Dependencies as links or relations to the tickets they wait on, not as prose.
- One deliverable per ticket.

## Comments

- One line: what changed, and the link that proves it (PR, commit, file). "Merged in #12; setup now lists Plane projects by name."
- A decision gets one more line with the reason.
- No greeting, sign-off, emoji, "I have" or "As requested", and no restating the ticket.
- Never a running log of every step. Tick the checklist for that.

## Fields

- Never invent a due date, priority, estimate, label or assignee. Set one only when the user gave it or the board's rule is plain (for example, new items are assigned to the user).
- Use the labels and states the board already has. Propose a new one as a question; do not create it unasked.

## Before writing

1. Draft the title, description and steps.
2. Show the user the exact text and where it will go, once for the whole set.
3. Write it when they say yes. Under `tracking=always` this confirmation is the only one for planned work; updates to those tickets while working need none (see [tasks.md](tasks.md)).

## When the user's own setup could be better

While reading a task, if something would trip up the next reader, say so once, as a question, with the fix you would make. One suggestion per task, the most useful one. Typical cases:

- The same steps sit in both the description and the checklist.
- A title or one-line description that does not say what done looks like.
- In progress with no due date, or overdue and still in to-do.
- One ticket holding several deliverables, or a parent whose sub-items are all done but it is still open.
- A structure the tool has a better home for (see the Recommendations in `trackers/<tool>.md`).

Never fix these silently, and do not repeat a suggestion the user turned down.
