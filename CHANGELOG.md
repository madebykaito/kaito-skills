# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [semver](https://semver.org).

## [Unreleased]

## [1.4.0] - 2026-11-20

### Added

- helpmekaito upgrades kaito-skills by itself. At the start of a task it looks for a newer release, at most once a day, moves your clone to the release tag and runs `./setup --upgrade` in the background; a later task says what changed. It never installs unreleased work and never asks.
- `kaito-self.sh mode auto|ask|off` chooses how upgrades behave (`update.mode`, default `auto`). `ask` asks first, `off` never checks. `snooze` silences a release for 7 days.
- `kaito-self.sh version`, `check` and `upgrade`, also as "what version of kaito" and "upgrade kaito" in chat or `/helpmekaito upgrade`.
- Uninstall from chat ("uninstall kaito") or with `kaito-self.sh uninstall`. It shows what would be removed and restored and does nothing without `--yes`. It works after the clone was deleted.
- Setup lists skills you already have under the same name as a kaito skill, and Claude Code plugins that ship one, and asks whether to replace the skills or disable the plugins. The default is no. Replaced skills are moved to `~/.kaito/backup`, and uninstall restores skills and plugins.
- `./setup --upgrade`: an unattended re-install that keeps every earlier answer and turns nothing new on.
- `./setup --duplicates`: ask again about same-name skills and plugins you said no to.
- `better-motion` skill (jakubkrehel/skills): what should animate, with exact duration, easing, scale and distance.
- `VERSION` file. Setup records the installed version and the clone's path in `state.json` and keeps a copy of itself in the store.

### Changed

- Setup's summary prints the update mode and the command to change it.
- A same-name skill of yours is no longer only skipped: setup asks about it. Saying no keeps the old behavior.
- Four marketing skills follow their upstream names: `analytics-tracking` is now `analytics`, `competitor-alternatives` is `competitors`, `page-cro` is `cro` (it also covers forms) and `schema-markup` is `schema`. The next `./setup` or upgrade removes the old links. Call them by the new names, and rename them in your `hot` list in `~/.kaito/config.json` if they are there.
- gstack 1.100.0.0 → 1.102.0.0: first-use check, owner answers, a ship-phase driver, founder resources as a command. kaito still registers none of gstack's always-on hooks; the destructive-command guard applies while `/careful` or `/guard` is loaded.
- `design-taste-frontend` is taste-skill 2.5.1: a company-website builder with its own kit of sections, photographs and icons (39 MB) and a checker that runs the page in a real browser. It needs Node 22+ and Chrome. In Claude Code its Stop hook holds the task until the checks pass. Its scripts fetch icons from jsDelivr and photographs from Wikimedia Commons and Picsum when the agent runs them.
- `better-*` and `interface-review` (jakubkrehel/skills): motion rules moved out of `better-ui` into the new `better-motion`; each single-discipline skill's report format is in its own `reporting.md`.
- `impeccable` 4.9.2 → 4.10.0 (engine 0.1.27): a defined mode for delegated and read-only critiques, saved audit scores. `init` now suggests `npx impeccable login` once; it is optional.
- `app-store-screenshots`: Google Play, macOS and Android, and a Next.js editor template the agent copies into your project.
- `frontend-design` (Anthropic), `vercel-react-best-practices` (29 new rules), `web-design-guidelines`, `copywriting` 2.3.6 and `brandkit` updated from upstream.
- stageshow kit: React 19, Vite 8, TypeScript 7, lucide-react 1.76, playwright-core 1.65. Node 20.19+ or 22.12+.
- cytoscape 3.30.4 → 3.35.0 in the research project template.

### Fixed

- `kaito-tasks.sh link` on Plane says the task already links the URL instead of failing with `plane 400`.

## [1.3.0] - 2026-11-19

### Added

- helpmekaito: Plane as a task manager. `kaito-tasks.sh` reads and writes Plane projects and modules with an API key (`login`), or helpmekaito uses the Plane MCP when there is no key.
- Each repo picks its own task manager from its `board:` line, so one machine can have repos on Trello, Plane and Obsidian.
- New Plane work items, sub-items and Trello cards are assigned to the person whose key is in use, also before the first `discover`.
- A project can have several trackers, each with a role (official or personal) and its own tracking setting: `kaito-tasks.sh tracker add|set|rm|list`, `--tracker <manager>`.
- Tracking is asked once per project and remembered (`always`, `never`, `ask`). With `always`, planned work becomes a parent ticket with sub-tickets and is kept current while you work.
- First use in a repo: `kaito-tasks.sh detect` reports which tracker the repo seems to live in, from ticket keys in the branch and commits, tracker links in the docs and name matches. helpmekaito proposes and asks; it never maps a tracker by itself.
- `kaito-tasks.sh link <task> <url>` attaches a PR or issue link to a task.
- For big work in a repo on GitHub, helpmekaito offers to open one issue linked both ways with the tracker ticket (`references/github-issues.md`). It always asks first.
- Writing rules for tickets and comments (`references/task-writing.md`) and a playbook per tracker (`references/trackers/`).
- Board structure memory refreshes itself on `pull` when it is older than `tasks.structure_ttl_hours` (default 24).

### Changed

- `kaito-tasks.sh` is now a thin CLI over `kaito-tasks.mjs` and one module per manager in `scripts/providers/`.

### Fixed

- Setup lists your Trello boards by name and lets you pick by number, `all` or `none`, instead of asking for board ids.
- Setup no longer asks for an Obsidian vault path. It reads the vaults Obsidian knows, asks only when Obsidian is the task manager, and says to set up Obsidian first when there is no vault.

## [1.2.0] - 2026-11-18

### Added

- Windows support through Git Bash. `setup.ps1` checks for Git, Node and bun, then runs `./setup`. Skills are linked with directory junctions, so no admin rights are needed.
- Docs in `docs/`: install per OS, using the skills, how it works, troubleshooting. The README has a quick start.
- CI on Windows and Alpine Linux, plus `tests/smoke.sh`, a real install and uninstall on every platform.
- `tests/docker.sh` runs the tests in Debian, Alpine and Fedora containers.
- `.gitattributes` keeps LF line endings in a Windows checkout.

### Changed

- Setup copies and links with `helpmekaito/scripts/kaito-sync.mjs` instead of `rsync` and `ln -s`, so it runs where `rsync` is missing.
- Codex leftovers are cleaned from `$CODEX_HOME/skills`, not always `~/.codex/skills`.

### Fixed

- `memory.path` and the Obsidian vault path are stored as typed, not rewritten by Git Bash.
- The Obsidian mirror works with Git for Windows' curl.
- `tests/run.sh` runs on busybox `xargs` (Alpine).
- JSON writes retry when Windows holds the file for a moment.

## [1.1.1] - 2026-11-18

### Changed

- gstack 1.99.5.0 → 1.100.0.0: shell locks hold on Ubuntu 26.04, `hono` pinned to 4.13.16 for five advisories, clearer skill descriptions in Claude Code, /ship review rounds counted per pull request.
- research-superpowers v0.41.1 → v0.47.0 (all 16 skills): personal-data check before analysis, per-chapter peer review for long manuscripts, a source-class rubric for web citations (`references/source-classes.md`), and `forward-search.py` in the project template.
- codegraph 1.6.2 → 1.6.3: security fixes for sensitive folders and the bundled Node.js, more accurate links.
- Upstream updates for skills that were clean copies:
  - `better-*` and `interface-review` (jakubkrehel/skills)
  - `content-strategy`, `copy-editing`, `copywriting`, `programmatic-seo`, `seo-audit` (coreyhaines31/marketingskills)
  - `impeccable`, `ponytail`, `ponytail-audit`, `ponytail-debt`, `ponytail-review`, `stageshow`, `higgsfield-generate`

## [1.1.0] - 2026-11-18

### Added

- Contributor docs: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 3.0), `SECURITY.md`.
- Issue forms, a PR template and `CODEOWNERS`.
- CI on macOS and Linux: `tests/run.sh` and `check-routes.sh` on every PR.
- Dependabot for GitHub Actions, stale, labeler and welcome workflows.
- Release workflow: a `vX.Y.Z` tag creates the GitHub Release.
- helpmekaito: Trello and Obsidian task sync (`kaito-tasks.sh`), project scan, `memory.path`.
- setup: task onboarding.

### Changed

- Tests run in parallel and clean up every temp folder.
- `LICENSE` is plain MIT so GitHub detects it.

### Fixed

- `THIRD_PARTY_LICENSES.md` now covers every vendored skill.

## [1.0.0] - 2026-11-17

First release.

[Unreleased]: https://github.com/madebykaito/kaito-skills/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/madebykaito/kaito-skills/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/madebykaito/kaito-skills/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/madebykaito/kaito-skills/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/madebykaito/kaito-skills/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/madebykaito/kaito-skills/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/madebykaito/kaito-skills/releases/tag/v1.0.0
