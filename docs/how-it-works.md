# How it works

## What setup puts where

| Path | What |
|---|---|
| `~/.kaito/store/<skill>` | A copy of each skill. Agents read skills from here, never from the repo. |
| `~/.kaito/config.json` | Your settings: hot list, gstack on or off, task manager, memory path. |
| `~/.kaito/state.json` | What setup added, so re-runs and `--uninstall` touch only that. Also the installed `version` and the `repo` it came from, which upgrades use. |
| `~/.kaito/backup` | Skills of yours that you let setup replace. Uninstall moves them back. |
| `~/.kaito/memory` | Notes `helpmekaito` keeps about you and each repo. Change it with `memory.path`. |
| `~/.kaito/.env` | Task manager credentials, written only by `kaito-tasks.sh login`. |
| `~/.claude/skills/<skill>` | A link to the store copy, for Claude Code. |
| `~/.agents/skills/<skill>` | A link for Codex: `helpmekaito` and your hot list. |

On macOS and Linux the links are symlinks. On Windows they are directory junctions.

Because agents read the store and not the repo, you can edit or switch branches in the repo without breaking a running session. Run `./setup` to publish your changes to the store.

## What setup changes in your settings

| File | Change | When |
|---|---|---|
| `~/.claude/settings.json` | A `skillOverrides` entry of `name-only` per skill | Always |
| `~/.claude/settings.json` | Allow rules for kaito scripts and `~/.kaito` | Only if you say yes |
| `~/.claude/settings.json` | The `ponytail` SessionStart hook | Only if you say yes |
| `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | A one-line `helpmekaito` nudge between markers | Only if you say yes |
| `~/.codex/config.toml` | `~/.kaito` added to `writable_roots` | Only if you say yes |
| `~/.claude/settings.json` | A plugin set to off in `enabledPlugins` | Only if you say yes, per plugin |
| Global git ignore | `.codegraph` | Default yes |

Your other settings are kept. Setup stops before changing anything if `settings.json` or `state.json` is not valid JSON.

## Skills you already have

If a skill with the same name is already in `~/.claude/skills` and is not one of ours, setup lists it and asks whether to replace it. The default is no: your copy wins and setup reports `skip (not ours)`. On a yes yours is moved to `~/.kaito/backup`, not deleted, and uninstall moves it back.

A Claude Code plugin can ship a skill with the same name too. Setup asks per plugin whether to disable it, which turns off the whole plugin. It does not edit marketplaces or other projects' plugin settings. A no is remembered, and names must match exactly.

## Upgrades

`helpmekaito` runs `kaito-self.sh auto` at the start of a task. At most once a day it reads the release tags of the clone's remote (`repo` in `state.json`). With a newer release and `update.mode` at `auto` (the default) it moves the clone to that tag and runs `./setup --upgrade` in the background, which asks nothing and keeps every earlier answer; the outcome is printed at the start of a later task. `ask` only reports the release, `off` never checks. The store keeps a copy of `setup`, so uninstall works without the clone.

## gstack

`gstack` is built with bun inside the store copy, rendered for Claude Code, and its sub-skills (`/review`, `/qa`, `/ship` and more) are linked one by one. A kaito skill with the same name wins over a gstack one.

## codegraph

Setup installs `@colbymchenry/codegraph` at the version in `codegraph.version` and connects it to Claude Code and Codex. It indexes a repo into a local graph, so the agent can find code in one call. Indexes live in `~/.kaito/codegraph`, linked from each repo's `.codegraph`.

## The router

`helpmekaito` reads a short domain map, picks at most three skills or one recipe, and says the route before it starts. It routes only to skills that are installed. When a task can be split, it can hand parts to other models your machine can reach.
