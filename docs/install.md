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
| `--no-gstack` | Skip the gstack build and links. |
| `--no-codegraph` | Skip the codegraph install. |
| `--uninstall` | Remove the links, the store, and the settings edits setup made. |
| `--purge` | `--uninstall`, and delete `~/.kaito` too. |

`KAITO_HOME` moves the store and config (default `~/.kaito`). `KAITO_ANSWERS="perms=y,nudge=n"` answers prompts by key, which is handy for scripts.

## Update

```bash
git pull
./setup
```

Run setup after every pull. It copies the new versions into the store and adds or removes links to match.

## Uninstall

```bash
./setup --uninstall
```

This removes only what setup added: its links, the store, its `skillOverrides` entries, and any optional edits you said yes to. Skills you had before are never touched. `--purge` also deletes `~/.kaito`, which holds your config, memory and task credentials.

## Check it worked

Start a new Claude Code session and type `/helpmekaito what can you do`. It lists the skill domains. In Codex, ask for `helpmekaito` by name.
