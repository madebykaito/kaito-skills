# Security policy

## Reporting a vulnerability

Report privately through GitHub: [open a security advisory](https://github.com/madebykaito/kaito-skills/security/advisories/new).

Do not open a public issue with details. If the advisory form does not work for you, email hello@madebykaito.com.

You get a reply within 7 days. Once the issue is confirmed, we agree on a fix and a disclosure date with you.

## Scope

In scope:

- Skill files (`SKILL.md`, references) that could make an agent do something harmful: hidden instructions, prompt injection, encoded payloads.
- Scripts in this repo, including `setup` and `helpmekaito/scripts/`.
- GitHub workflows in `.github/`.

Out of scope:

- Bugs in Claude Code, Codex or other agents. Report those to their makers.
- Bugs in upstream skills that are not in our copy. Report those upstream too.

## Supported versions

Only the latest release gets fixes.

## How skills are reviewed

Skills are instructions an agent follows, so they are reviewed like code.

- Every changed line of `SKILL.md`, references and scripts is read.
- Hidden or encoded text is rejected.
- Scripts that use the network, pipe to a shell or write outside the project need a stated reason.
- Vendored skills name the upstream commit they came from.
