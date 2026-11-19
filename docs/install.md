# Install

You need `git`, `node` and `npm` (CI tests Node 22). [Bun](https://bun.sh) is needed only for `gstack`. Skip it with `--no-gstack`.

Setup copies the skills into `~/.kaito/store` and links them into the folders Claude Code and Codex read. It never edits the repo, and `--uninstall` undoes every change it made.

## macOS

```bash
brew install node oven-sh/bun/bun
```

```bash
git clone https://github.com/madebykaito/kaito-skills.git
cd kaito-skills
./setup
```

## Linux

Install the tools with your package manager, then run setup the same way.

| Distro | Command |
|---|---|
| Debian, Ubuntu | `sudo apt install git nodejs npm` |
| Fedora | `sudo dnf install git nodejs npm` |
| Alpine | `sudo apk add git nodejs npm bash curl` |
| Arch | `sudo pacman -S git nodejs npm` |

For bun, run `curl -fsSL https://bun.sh/install | bash` (it reads the script from bun.sh), or pass `--no-gstack`.

```bash
git clone https://github.com/madebykaito/kaito-skills.git
cd kaito-skills
./setup
```

## Windows

Setup runs in Git Bash, the same shell Claude Code uses on Windows. Install the tools once, in PowerShell:

```powershell
winget install --id Git.Git -e
```

```powershell
winget install --id OpenJS.NodeJS.LTS -e
```

```powershell
winget install --id Oven-sh.Bun -e
```

Open a new terminal so the tools are on your PATH. Then, in PowerShell:

```powershell
git clone https://github.com/madebykaito/kaito-skills.git
cd kaito-skills
.\setup.ps1
```

`setup.ps1` checks the tools, prints the `winget` command for anything missing, then runs `./setup` in Git Bash. In Git Bash you can run `./setup` directly.

Windows notes:

- Skills are linked with directory junctions. They need no admin rights and no Developer Mode.
- Your user folder must not contain a space. Setup refuses a path like `C:\Users\Jane Doe` and links nothing. Use WSL in that case.
- If you run Claude Code or Codex inside WSL, run setup inside WSL too. WSL has its own home folder and counts as Linux.
- gstack's compiled tools are unsigned. With Smart App Control on, Windows blocks them. See [troubleshooting](troubleshooting.md#windows-smart-app-control).

## Prompts and flags

Setup asks before each optional step. With no terminal, or with `--yes`, it takes the default. The prompts and defaults are listed in the [main README](../README.md#setup).

| Flag | Effect |
|---|---|
| `--yes` | Take the default without asking. |
| `--upgrade` | Re-install without asking anything. Every earlier answer is kept and nothing new is turned on. |
| `--no-gstack` | Skip the gstack build and links. |
| `--no-codegraph` | Skip the codegraph install. |
| `--uninstall` | Remove the links, the store, and the settings edits setup made. Put back the skills and plugins setup replaced. |
| `--purge` | `--uninstall`, and delete `~/.kaito` too. |

`KAITO_HOME` moves the store and config (default `~/.kaito`). `KAITO_ANSWERS="perms=y,nudge=n"` answers prompts by key, which is handy for scripts.

## Skills and plugins with the same name

Setup lists two kinds of duplicates and asks about each. The default is no.

- Skills you already have under the same name as a kaito skill. On a yes, yours are moved to `~/.kaito/backup` and the kaito ones are linked. Nothing is deleted.
- Claude Code plugins that ship a skill with the same name. Setup asks per plugin. On a yes it sets the plugin to off in `enabledPlugins` in `~/.claude/settings.json`. That turns off the whole plugin, not just the one skill.

A no is remembered, so setup does not ask again. Names must match exactly. Setup does not edit plugin marketplaces or the plugin settings of other projects. Uninstall moves your skills back and turns the plugins on again.

## Update

You do not have to do anything. At the start of a task `helpmekaito` checks for a newer release, at most once a day. The check reads the release tags of your clone's remote and sends nothing else anywhere. When there is a newer release it moves the clone to that tag, runs `./setup --upgrade` and tells you what changed. New sessions use the new skills.

`./setup --upgrade` asks nothing and changes no earlier answer: nothing new is turned on and no duplicate is replaced. The upgrade needs a clean clone on its default branch, and it only ever installs a release, never unreleased work. If it cannot run it says why and goes on with your task. See [troubleshooting](troubleshooting.md#upgrade-skipped).

You choose how it behaves:

```bash
sh ~/.kaito/store/helpmekaito/scripts/kaito-self.sh mode ask
```

| Mode | Effect |
|---|---|
| `auto` | Upgrade to each release and say what changed. The default. |
| `ask` | Say that a release is out and ask: now, later (quiet for 7 days) or stop checking. |
| `off` | Never check. |

The same script has `version`, `check`, `upgrade` (do it now) and `snooze`. In chat, "upgrade kaito" and "what version of kaito" do the same.

By hand it is still:

```bash
git pull
./setup
```

Run setup after every pull. It copies the new versions into the store and adds or removes links to match.

## Uninstall

```bash
./setup --uninstall
```

This removes only what setup added: its links, the store, its `skillOverrides` entries, and any optional edits you said yes to. Skills you had before are never touched. The ones setup moved to `~/.kaito/backup` are put back, and plugins it turned off are turned on again. `--purge` also deletes `~/.kaito`, which holds your config, memory and task credentials.

You can also say "uninstall kaito" in chat, or run the script yourself. With no `--yes` it only lists what it would remove and restore:

```bash
sh ~/.kaito/store/helpmekaito/scripts/kaito-self.sh uninstall
```

Add `--yes` to do it, and `--yes --purge` to delete `~/.kaito` too. This works even after the clone was deleted. Start a new session afterwards; the open one still has the old skills loaded.

## Check it worked

Start a new Claude Code session and type `/helpmekaito what can you do`. It lists the skill domains. In Codex, ask for `helpmekaito` by name.
