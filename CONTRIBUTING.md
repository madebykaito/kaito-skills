# Contributing

Thanks for helping. Fixes, new skills and better docs are all welcome.

This is a one-person project. Expect a first reply within 7 days.

Follow the [repository rules](AGENTS.md).

## Quick start

```bash
git clone https://github.com/<you>/kaito-skills.git
cd kaito-skills
./setup
```

`setup` needs `git`, `node` and `npm`. `gstack` also needs [bun](https://bun.sh); pass `--no-gstack` to skip it.

Run the catalog checks before opening a PR.

```bash
helpmekaito/scripts/check-routes.sh
node tools/check-layout.mjs
node tools/validate-skills.mjs
node tools/privacy-scan.mjs
```

The route check must print `routes ok`. Build agents run only their own test files. The lead runs `tests/run.sh` once on the combined branch. CI runs the suite and `tests/smoke.sh` on Ubuntu, macOS and Alpine. Use local fixtures for tests so they never call real services.

Keep private data out of the repo, including in filenames and media. Use the fictional owner fixtures. The privacy scanner checks for emails, phone numbers, key shapes and media metadata. A maintainer can add a local denylist at `~/.kaito/privacy-denylist.txt`. Privacy tests read denylisted names from a local file and keep the names out of code.

To test Linux from a Mac or Windows machine, run the same checks in Docker containers for Debian, Alpine and Fedora:

```bash
tests/docker.sh
```

Scripts must run in plain `sh` on all three platforms. Do not use `rsync`, `ln -s` for links that setup manages, or GNU-only flags. Use `helpmekaito/scripts/kaito-sync.mjs` to copy and link.

## Adding a skill

Put a standalone skill in `<skill>/SKILL.md`. Put related skills from the same family in `<bundle>/<skill>/SKILL.md`. A bundle has one `bundle.json` with its `name`, `source`, `license` and array of skill folder names in `skills`. If a skill shares its bundle's name, use `<bundle>/<bundle>/SKILL.md`. Setup links each member by its own name. The layout check reads [the allowlist](tools/layout-allowlist.json) for exact groups of unrelated names and their reasons.

1. Vendor runtime files only, including `SKILL.md`, references, scripts and assets. Keep upstream `LICENSE` and `NOTICE` files. Leave out upstream tests, CI config, changelogs and TODOs.
2. Keep build output and dependencies out of Git. Use regular folders and files.
3. Add a skill row to `README.md` and `THIRD_PARTY_LICENSES.md`. Give the source, author and license. Include the upstream license text if needed and name the vendored upstream commit in the PR. Add prerequisites under “Known limits” in the README.
4. Add a row to the matching file under `helpmekaito/references/domains/`. Run `check-routes.sh` until it prints `routes ok`.

## Editing a skill

The `description` in the frontmatter decides when the skill fires. Keep `name` and `description` accurate.

If you change a description, list in the PR:

- 3 prompts that should fire the skill.
- 2 prompts that should not.

Upstream skills keep their original license and attribution. Changes are fine.

## Pull requests

- One change per PR. Small PRs get merged faster.
- Show evidence: what you ran and what came out. A transcript or a before and after is enough.
- Say if an AI agent wrote the change, and which one. Write the summary yourself.
- Commit as the repo's configured Git user and leave out AI co-author and generated-with trailers.
- Commit messages use a short prefix: `feat:`, `fix:`, `docs:`, `test:`, `chore:`.
- CI must pass. The maintainer reviews and merges.

## What we won't merge

- Hidden or encoded text in a skill: base64 blobs, invisible Unicode, "ignore previous instructions".
- Scripts that call the network, pipe to a shell or touch files outside the project, without a clear reason in the PR.
- Secrets, keys or tokens of any kind.
- Build output or dependencies.
- Runtime stubs or unrelated bulk renames and formatting changes.

## Reporting issues

- Bugs and new skill ideas: open an issue from the templates.
- A skill that fires when it shouldn't is a bug.
- Security problems: see [SECURITY.md](SECURITY.md). Do not open a public issue.

## Labels

- `good first issue`: small and well defined. Good place to start.
- `help wanted`: the maintainer would like a hand.
- `needs-info`: waiting on you. Closed after 30 days without a reply.
- `keep-open`: never marked stale.

## Releases

Versions follow [semver](https://semver.org). The maintainer updates `CHANGELOG.md` and pushes a `vX.Y.Z` tag. A workflow then creates the GitHub Release with generated notes.

## Conduct

Everyone here follows the [Code of Conduct](CODE_OF_CONDUCT.md).
