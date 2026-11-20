# Runners

How to hand a task to a model. Get the runner and the exact model id from `node scripts/kaito-models.mjs resolve <vendor-or-runner> <tier>` ([models.md](models.md)). `scripts/models-available.sh` lists every model each runner can reach.

Every brief is self-contained: the goal, the files, what done looks like, and what not to touch. The delegate has none of this conversation. If the task uses a skill, name the skill in the brief so the delegate loads it.

Check the result yourself before reporting it. A delegate's summary is a claim, not proof.

## Host subagent (default)

- **Claude Code**: the Agent tool with `model` set to `haiku`, `sonnet`, `opus` or `fable`.
- **Codex, opencode, others**: the host's own subagent or task tool, with its model option if it has one.

Runs in the same workspace with the same permissions. Use this unless [models.md](models.md) says to leave the host.

## Other CLIs

Start read-only. Allow writes only when the task is to edit files.

| Runner | Read-only run | Run that edits files |
|---|---|---|
| Claude Code | `claude -p --model <id> --permission-mode plan "<brief>"` | `claude -p --model <id> "<brief>"` |
| Codex | `codex exec -m <id> -s read-only "<brief>"` | `codex exec -m <id> -s workspace-write "<brief>"` |
| Cursor | `cursor-agent -p --mode plan --model <id> "<brief>"` | `cursor-agent -p --model <id> "<brief>"` |
| opencode | `opencode run --agent plan --model <provider/id> "<brief>"` | `opencode run --model <provider/id> "<brief>"` |
| Gemini CLI | `gemini -m <id> -p "<brief>"` | same, with its approval flags |
| Copilot CLI (untested) | `copilot -p "<brief>" -s --model=<id>` | same, with `--allow-tool=<tool>` for each tool it needs |
| Ollama (untested) | `ollama run <model> "<brief>"` | none: text in, text out |

Verified on 2026-11-16: `claude`, `codex` and `cursor-agent`. The `opencode` and `gemini` rows are from their docs. Run `<cli> --help` once before first use on a machine and correct the flags if they differ.

Where the model list comes from, checked on 2026-11-20 for the first five:

| Runner | Found as | Models listed by |
|---|---|---|
| Claude Code | `claude` | its aliases `haiku`, `sonnet`, `opus`, `fable`; each points at the newest of its family |
| Codex | `codex` | `~/.codex/models_cache.json`, which Codex keeps current |
| Cursor | `cursor-agent` | `cursor-agent --list-models` |
| opencode | `opencode` | `opencode models` |
| Gemini CLI | `gemini` | no listing command; the ids are read from the installed CLI's own files. If they cannot be found, no Gemini model is listed |
| Copilot CLI (untested) | `copilot` | no listing command; `/model` inside a session shows them. The resolver cannot pick one: pass the id the user names |
| Ollama (untested) | `ollama` | `ollama ls` (models already pulled) |

**Untested:** the Copilot CLI and Ollama rows come from their official docs (docs.github.com "Copilot CLI programmatic reference", docs.ollama.com "CLI reference") and have not been run. Neither was installed when they were written. Say so to the user before the first use, and run `copilot help` or `ollama --help` to check the flags.

Notes:
- Do not pass flags that skip all permission checks (`--dangerously-skip-permissions`, `--force`, `--yolo`) unless the user asked for that.
- opencode reaches Anthropic, OpenAI, Google, xAI, OpenRouter and local models through one `provider/id` scheme. `opencode models <provider>` lists them. When it is installed, it is the simplest way to reach a vendor that has no CLI of its own.
- Cursor ids carry the effort level, for example `gemini-4-argon-high`.
- Copilot CLI: `-p` runs one prompt and exits, `-s` prints only the answer. `--allow-all-tools` and `--allow-all` skip its permission checks: only when the user asked.
- Ollama runs local models that cannot read the repo or edit files on their own, so paste the content into the brief. `ollama launch claude --model <model>` starts an agent CLI on a local model instead. Most Ollama names carry no family word, so use one only when the user names it.
- A run that fails because the model is unavailable or out of quota: `node scripts/kaito-models.mjs fail <runner> <model-id>`, then resolve again.
- Long runs go in the background. Do not block the turn on a call that can take minutes.

## API only (text in, text out)

When a key is set but no agent CLI can reach the vendor, the model can still read text and answer. It cannot read the repo or edit files, so use it only for a second opinion on a diff, a copy draft or a critique, with the content pasted into the request.

Both endpoints are OpenAI-compatible chat completions:

- OpenRouter: `https://openrouter.ai/api/v1/chat/completions` with `OPENROUTER_API_KEY`. Live model list: `GET https://openrouter.ai/api/v1/models/user`.
- xAI: `https://api.x.ai/v1/chat/completions` with `XAI_API_KEY`.

Read the key from the environment inside the command. Never print it or write it to a file.
