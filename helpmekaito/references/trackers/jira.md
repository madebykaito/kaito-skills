# Jira

Read with [task-writing.md](../task-writing.md). Jira is reached through its MCP only; `kaito-tasks.sh` keeps the project's `tracker:` line and nothing else. Newer Jira calls an issue a work item and a project a space; the structure is the same.

## Structure

| Level | Use it for |
|---|---|
| Epic | Work measured in weeks that several stories or tasks deliver together. |
| Story | The smallest unit of user-facing value. Fits in one sprint. |
| Task | Work that is not user-facing: a migration, a refactor, a chore. |
| Bug | A problem that impairs or prevents a function. |
| Sub-task | One piece of a story, task or bug. Cannot have children. |
| Component | A feature area or workstream (company-managed projects). |
| Version | Features and fixes released together. Set before work starts, if the team uses versions. |
| Status | A workflow step. Each belongs to a category: To do, In progress, Done. |
| Link | blocks / is blocked by, duplicates, relates to, causes. |

- Use the issue types, components and workflow the project already has. Read them through the MCP before the first write and keep them in `managers/jira.md`.
- Dependencies are issue links, not prose.
- Not every story needs an epic. Use one when the work spans several stories.

## Formats

- Description and comments are Atlassian Document Format (ADF) on the v3 API: a `doc` of paragraphs, headings, bullet and ordered lists, code blocks, tables, panels. The MCP usually takes Markdown and converts it. Never send wiki markup.
- Summary: an action and its object, 255 characters at most.
- Story description: "As a <who>, I want <what>, so that <why>" when the team writes stories that way, then acceptance criteria. Describe the goal, not the UI.
- Task description: goal, scope, acceptance criteria, links.
- Bug description: numbered steps to reproduce, expected result, actual result, environment. One bug per issue.
- Acceptance criteria: clear, testable, about the outcome and not the recipe, each one independent. Given / When / Then if the team uses it.

## Fields

- Story points, sprint, fix version, priority, assignee, component: set only what the user gave or the project's rule makes plain. Never put an issue in the active sprint unasked.
- Move status only along the project's workflow transitions. Done means a status in the Done category.
- Many sub-tasks under one issue is a sign to split the issue.

## Recommendations to offer, once, as a question

- Multi-PR work as loose tasks: an epic with stories or tasks under it.
- A story that will not fit in a sprint: split it by outcome.
- Acceptance criteria like "should look good": rewrite as something a test or a look can settle.
- "Blocked" written in a comment: an is-blocked-by link.
- A finished-meaning status that sits outside the Done category: it breaks sprint completion; ask an admin to fix the mapping.

## Limits worth knowing

- Writes to one issue are limited to about 20 in 2 seconds; a 429 carries `Retry-After`. Retry only reads.
- A Rovo or other agent assigned an issue works from its summary and description first, so those must stand alone.

Sources: support.atlassian.com/jira-cloud-administration (what-are-issue-types, what-is-a-workflow-status), support.atlassian.com/jira-software-cloud (what-are-jira-components, what-is-a-version, link-issues, configure-columns, collaborate-on-work-items-with-ai-agents), developer.atlassian.com/cloud/jira/platform (rest/v3/intro, apis/document/structure, rate-limiting), atlassian.com/agile/project-management (user-stories, epics, epics-stories-themes), atlassian.com/work-management/project-management/acceptance-criteria, atlassian.com/software/jira/templates/bug-report.
