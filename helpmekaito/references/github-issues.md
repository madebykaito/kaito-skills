# GitHub issues for big work

helpmekaito does not treat GitHub Issues as a task manager. It opens one issue for a large piece of work so the work has a public home next to the code, and links it to the tracker ticket. How to write the issue is in [trackers/github-issues.md](trackers/github-issues.md).

## When to offer one

All of these hold:

- The repo has a GitHub remote (`kaito-tasks.sh detect` prints `github: yes`) and `gh auth status` succeeds.
- The work is big: a new feature, more than one pull request, a change to a public interface, or the user calls it big.
- The repo uses issues (it has some, or has issue templates). A repo that tracks everything elsewhere and has issues turned off gets no offer.

Small tasks stay in the tracker only.

## Always ask

Offer it in one line and wait for a yes, whatever the project's `tracking` setting: "This spans several PRs. Open a GitHub issue for it, linked to ALL-27?" An issue is public in a public repo and notifies watchers, so it is never created unasked and never to test. If the user says no, do not offer again for this piece of work.

## Create and link

1. Search first so nothing is filed twice: `gh issue list --search "<key words>" --state all`.
2. Draft the title and body to [task-writing.md](task-writing.md), using the repo's issue form headings if `.github/ISSUE_TEMPLATE` has one. Put the tracker ticket's key and link in the body. Show the draft.
3. On yes: `gh issue create --title "<title>" --body-file <file>`; add `--label` only with labels that exist.
4. Link both ways. For a Trello, Plane or Obsidian ticket: `kaito-tasks.sh --tracker <manager> link <task> <issue-url> "GitHub issue #<n>"`, naming the tracker the ticket lives in, because a project can have more than one. For Jira, Asana or another tracker reached through its MCP, add the issue URL with that MCP as a link on the ticket (a comment if it has no link field); the script does not write to those.
5. Parts that will be separate pull requests can be sub-issues, if the user wants them on GitHub as well as in the tracker. Otherwise the tracker's sub-tickets are enough; do not keep two copies of the breakdown.
6. Each pull request says `Closes #<n>` (or `Refs #<n>` when it is one of several), and the tracker ticket gets a one-line comment with the PR link.

## Never

- Create, close, relabel or assign an issue the user did not ask about.
- Paste private tracker content, customer names or internal links into an issue on a public repo. Check `gh repo view --json visibility` when unsure.
- Keep the same status in two places: the tracker ticket holds progress, the issue holds the public discussion.
