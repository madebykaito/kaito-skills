# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [semver](https://semver.org).

## [Unreleased]

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

[Unreleased]: https://github.com/madebykaito/kaito-skills/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/madebykaito/kaito-skills/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/madebykaito/kaito-skills/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/madebykaito/kaito-skills/releases/tag/v1.0.0
