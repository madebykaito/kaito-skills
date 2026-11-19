# GitHub Issues

Read with [task-writing.md](../task-writing.md) and [github-issues.md](../github-issues.md), which says when to open an issue at all. This file is how to write one well. Everything goes through `gh`.

## Structure

| Level | Use it for |
|---|---|
| Issue | One piece of work, or the parent of a larger one. |
| Sub-issue | An independently shippable part. Up to 100 per parent, eight levels deep, across repos. |
| Task list | `- [ ]` steps inside one issue. |
| Issue type | task, bug or feature, where the organisation has types. |
| Label | Area or kind. Use the repo's existing labels. |
| Milestone | A release or date the issue belongs to. |
| Issue form | The repo's own template in `.github/ISSUE_TEMPLATE`. Use it when there is one. |
| Project field | Status, iteration and the like, if the repo uses a project. |

- A pull request closes its issue with `Closes #12` in the PR description. It works only for PRs into the default branch, and each issue needs its own keyword.
- Blocked-by and blocking are issue dependencies, not prose.

## Formats

- The body is GitHub Markdown.
- Title: descriptive, written for someone new to the codebase.
- Body, in order: problem or goal, scope, acceptance criteria, where to look (files or area), how to test (the command), links. Follow the repo's issue form headings when it has one.
- Bug: steps to reproduce, expected, actual, version or environment. One bug per issue.

## Fields

- Labels, milestone, assignees and type are dropped silently without push access; check the created issue.
- Do not assign people or set a milestone unless the user said so.
- Default labels (bug, enhancement, documentation, good first issue) mean what GitHub says they mean; do not repurpose them.

## Recommendations to offer, once, as a question

- One large issue: split into sub-issues so the work can run in parallel and each PR stays small.
- The same status kept in an issue and in the tracker ticket: pick one home, and link from the other.
- A repo with no issue templates that takes outside contributions: a bug form and a feature form.

## An issue a coding agent can take

GitHub's own advice is to treat the issue as the prompt: a clear problem, complete acceptance criteria (say whether tests are expected), and directions to the files to change. Keep each issue atomic. Do not hand an agent a broad refactor, security or auth work, anything production-critical, or an ambiguous task. Build, test and lint commands belong in the repo's `AGENTS.md` or `.github/copilot-instructions.md`, not repeated in every issue.

## Limits worth knowing

- Creating an issue notifies watchers. Never create one to test.
- Make writes one at a time, at least a second apart; about 80 content-creating requests a minute at most. Honor `retry-after`.

Sources: docs.github.com/en/issues (about-issues, adding-sub-issues, managing-issue-types-in-an-organization, linking-a-pull-request-to-an-issue, managing-labels, about-milestones, best-practices-for-projects, understanding-fields), docs.github.com/en/communities (syntax-for-issue-forms), docs.github.com/en/rest (issues/issues, rate-limits-for-the-rest-api, best-practices-for-using-the-rest-api), docs.github.com/en/copilot/tutorials/coding-agent/get-the-best-results.
