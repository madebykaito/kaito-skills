# Contributing

Thanks for helping. Fixes, new skills and better docs are all welcome.

This is a one-person project. Expect a first reply within 7 days.

## Quick start

```bash
git clone https://github.com/<you>/kaito-skills.git
cd kaito-skills
./setup
```

`setup` needs `git`, `node` and `npm`. `gstack` also needs [bun](https://bun.sh); pass `--no-gstack` to skip it.

Before you open a PR, run both checks:

```bash
tests/run.sh
helpmekaito/scripts/check-routes.sh
```

`tests/run.sh` must end with no `FAIL` lines. `check-routes.sh` must print `routes ok`. CI runs both on macOS, Linux (Ubuntu and Alpine) and Windows (Git Bash), plus `tests/smoke.sh`, a real install and uninstall into a throwaway home.

To test Linux from a Mac or Windows machine, run the same checks in Docker containers for Debian, Alpine and Fedora:

```bash
tests/docker.sh
```

Scripts must run in plain `sh` on all three platforms. Do not use `rsync`, `ln -s` for links that setup manages, or GNU-only flags. Use `helpmekaito/scripts/kaito-sync.mjs` to copy and link.

## Adding a skill

Each top-level folder is one skill with a `SKILL.md`.

1. Put the skill in its own top-level folder. No submodules, no symlinks.
2. Copy only what runs: `SKILL.md`, references, scripts and assets. Leave out upstream tests, CI config, changelogs and TODOs.
3. Never commit build output or dependencies (`node_modules/`, `dist/`, binaries). Add them to `.gitignore`.
4. Add a row to the matching table in `README.md`, in the same short voice. If the skill needs a key, a paid package or a setup step, add a line under "Known limits".
5. Add the skill to the matching file in `helpmekaito/references/domains/`, then run `check-routes.sh` until it prints `routes ok`.

### Skills from someone else

You can vendor a skill from another repo if its license allows it.

- Keep the upstream `LICENSE` and `NOTICE` files inside the skill folder.
- Add a row to `THIRD_PARTY_LICENSES.md` with source, author and license. Add the license text if it is not already there.
- Name the upstream commit you copied from in the PR.

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
- Commit messages use a short prefix: `feat:`, `fix:`, `docs:`, `test:`, `chore:`.
- CI must pass. The maintainer reviews and merges.

## What we won't merge

- Hidden or encoded text in a skill: base64 blobs, invisible Unicode, "ignore previous instructions".
- Scripts that call the network, pipe to a shell or touch files outside the project, without a clear reason in the PR.
- Secrets, keys or tokens of any kind.
- Build output or dependencies.
- Bulk PRs that rename or reformat many skills at once.

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
