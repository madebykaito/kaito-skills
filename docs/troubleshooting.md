# Troubleshooting

## A skill does not show up

- Start a new agent session. Skills are read when a session starts.
- Check the link: `ls -l ~/.claude/skills/<skill>`. It should point into `~/.kaito/store`.
- If setup printed `skip (not ours): ...`, a skill with that name was already there and you kept it. Run `./setup` again and say yes to replacing it, or remove or rename yours first.
- In Codex only `helpmekaito` and the hot list are linked. Ask `helpmekaito` for the skill by name.

## A skill or plugin of mine is gone

You said yes when setup asked to replace a same-name skill or disable a plugin. The skill is in `~/.kaito/backup`. To get everything back, uninstall (`./setup --uninstall`): it moves the skills back and turns the plugins on again. To get one skill back and keep the rest, remove the kaito link at `~/.claude/skills/<skill>` and move your folder there from `~/.kaito/backup`. To get a plugin back, set it to `true` under `enabledPlugins` in `~/.claude/settings.json`.

## Upgrade skipped

`helpmekaito` prints `upgrade skipped: <reason>` and the command to upgrade by hand. Your task goes on with the installed version. The usual reasons:

| Reason | Fix |
|---|---|
| The clone has changes that are not committed | Commit or stash them, or upgrade by hand. |
| The clone is not on its default branch | Switch back to it in the clone (`git switch main`). |
| The clone is gone or was moved | Clone again and run `./setup` there. |
| Setup failed | Run `./setup` in the clone and read what it prints. |

By hand: `cd <clone> && git pull && ./setup`. Offline, the check prints nothing and tries again later.

## Turn automatic upgrades off

```bash
sh ~/.kaito/store/helpmekaito/scripts/kaito-self.sh mode off
```

`mode ask` asks before each upgrade, `mode auto` turns them back on. `snooze` silences the current new release for 7 days. In chat: "kaito, stop upgrading by yourself".

## `another setup is running`

A setup was cut off. If no other setup is running, remove the lock and run it again:

```bash
rmdir ~/.kaito/.setup.lock
```

## `... is not valid JSON`

Setup will not edit a broken `~/.claude/settings.json` or `~/.kaito/state.json`. Fix the file, or delete `state.json` (setup rebuilds it), then run setup again.

## `setup needs bun on PATH for gstack`

Install bun (see [install](install.md)) or run `./setup --no-gstack`. To turn gstack off for good, set `"gstack": false` in `~/.kaito/config.json`.

## gstack build or browser download fails

gstack downloads Chromium for its browser skills. Behind a proxy or offline this can fail. Run setup again once you are online, or use `--no-gstack`.

## Windows

### `must not contain spaces`

Your user folder has a space in it, such as `C:\Users\Jane Doe`. Setup does not support that yet, because Claude Code reads skills from that folder and setup cannot safely link into it. Run Claude Code and setup inside WSL instead. `KAITO_HOME` can move the store, but not the folder the agent reads.

### Scripts fail with `\r` or `bad interpreter`

The checkout has Windows line endings. The repo's `.gitattributes` prevents this for clones made after v1.2.0. For an older clone, delete it and clone again.

### Windows Smart App Control

gstack builds its tools on your machine, unsigned. With Smart App Control on, Windows blocks them and Git Bash shows `Permission denied`. Turn Smart App Control off, run gstack inside WSL, or install with `--no-gstack`. The other skills are not affected.

### Links show as folders

That is expected. On Windows the links are directory junctions, which Explorer shows as folders. Deleting a junction removes only the link, not the folder it points to.

## Still stuck

Open an issue with the bug form: https://github.com/madebykaito/kaito-skills/issues/new/choose. Include your OS, `node -v`, and the last lines setup printed. Never paste the contents of `~/.kaito/.env`.
