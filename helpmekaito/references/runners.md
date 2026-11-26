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

Before the call, run `node ~/.kaito/store/helpmekaito/scripts/kaito-usage.mjs consent check <runner> <model>` with the runner name from the table in lower case (`claude`, `codex`, `cursor-agent`, `opencode`, `gemini`). `ask`: the CLI is running on an API key, so the call is billed per token; ask the user once, naming the model, and on a yes run `consent yes <model>` ([usage.md](usage.md)). `ok`: a logged-in CLI on a subscription, no question.

| Runner | Read-only run | Run that edits files |
|---|---|---|
| Claude Code | `claude -p --model <id> --permission-mode plan "<brief>"` | `claude -p --model <id> "<brief>"` |
| Codex | `codex exec -m <id> -s read-only "<brief>"` | `codex exec -m <id> -s workspace-write "<brief>"` |
| Cursor | `cursor-agent -p --mode plan --model <id> "<brief>"` | `cursor-agent -p --model <id> "<brief>"` |
| opencode | `opencode run --agent plan --model <provider/id> "<brief>"` | `opencode run --model <provider/id> "<brief>"` |
| Gemini CLI | `gemini -m <id> -p "<brief>"` | same, with its approval flags |
| Copilot CLI (untested) | `copilot -p "<brief>" -s --model=<id>` | same, with `--allow-tool=<tool>` for each tool it needs |
| Ollama | `ollama run <model> "<brief>"`, or without the CLI see [Ollama](#ollama-local-bulk-drafts-and-translation) | none: text in, text out |

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
| Ollama | the server at `OLLAMA_HOST` (default `http://127.0.0.1:11434`) | `GET /api/tags`, the models already pulled. No CLI needed |

**Untested:** the Copilot CLI row comes from its official docs (docs.github.com "Copilot CLI programmatic reference") and has not been run. It was not installed when it was written. Say so to the user before the first use, and run `copilot help` to check the flags. The Ollama HTTP runner below is tested against a fake server; a run against a real pulled model is still owed.

Notes:
- Do not pass flags that skip all permission checks (`--dangerously-skip-permissions`, `--force`, `--yolo`) unless the user asked for that.
- opencode reaches Anthropic, OpenAI, Google, xAI, OpenRouter and local models through one `provider/id` scheme. `opencode models <provider>` lists them. When it is installed, it is the simplest way to reach a vendor that has no CLI of its own.
- Cursor ids carry the effort level, for example `gemini-4-argon-high`.
- Copilot CLI: `-p` runs one prompt and exits, `-s` prints only the answer. `--allow-all-tools` and `--allow-all` skip its permission checks: only when the user asked.
- Ollama runs local models that cannot read the repo or edit files on their own, so paste the content into the brief. `ollama launch claude --model <model>` starts an agent CLI on a local model instead.
- A run that fails because the model is unavailable or out of quota: `node scripts/kaito-models.mjs fail <runner> <model-id>`, then resolve again.
- Windows: a CLI installed only as a `.cmd` or `.bat` file is found but its models cannot be listed, so the resolver picks nothing from it. npm installs also add a plain script, which works.
- Long runs go in the background. Do not block the turn on a call that can take minutes.

## Ollama: local bulk drafts and translation

Free, local, private: nothing leaves the machine, so there is no consent question (`consent check ollama <model>` prints `ok`; a cloud model, whose name ends in `cloud`, prints `ask`). Use it for many small, well-specified pieces: caption and post drafts, subject-line variants, and translation. Not for code or anything that needs judgment.

Pick the model: `node scripts/kaito-models.mjs resolve ollama <light|standard|hard>`. It asks the server at `OLLAMA_HOST` (default `http://127.0.0.1:11434`) for the pulled models and prints `ollama <model>`. `mid` is accepted for `standard` and `heavy` for `hard`. A line that starts with `host:` means Ollama is not running or nothing of that tier is pulled: do the work on the host's model and say so. Embedding and cloud models are never picked.

| Tier | Parameter size |
|---|---|
| light | up to 4B |
| standard | over 4B, up to 14B |
| hard | over 14B |

There is no frontier tier locally. Within a tier the biggest model wins, then the newest pull. The size is the server's `parameter_size`, or the `:7b` part of the name when the server gives none; a model with neither is not placed.

Run one prompt (the prompt on stdin, the text on stdout; works without the `ollama` CLI):

```
printf '%s' "<prompt>" | node scripts/kaito-ollama.mjs run <model>
```

If the CLI is installed, `ollama run <model> "<prompt>"` does the same.

Translate: add `--translate-to <code>` (`bn`, `hi`, `ta`, `en`, and other ISO 639-1 codes; an unknown code is passed as the language name). The input text is wrapped in a translate-only instruction, so send just the text.

```
printf '%s' "Good morning" | node scripts/kaito-ollama.mjs run <model> --translate-to bn
```

Bulk: a JSONL file with one prompt per line, a JSON string or an object `{"id": "...", "prompt": "..."}`.

```
node scripts/kaito-ollama.mjs bulk <model> prompts.jsonl --out results.jsonl --concurrency 2 [--translate-to bn]
```

Each output line is `{"i": <line number from 0>, "id": ..., "text": "..."}`, or `{"i": ..., "error": "..."}` for a line that failed. Output is always in input order, whatever finished first. At most `--concurrency` requests run at once (default 2; a laptop with one loaded model gains little above 2). The exit code is 1 when any line failed. `--timeout <sec>` caps each request (default 300). Read the drafts before using them: a small model's Bengali or Hindi needs a native check.

If a run fails because the model is gone, run `kaito-models.mjs fail ollama <model>` and resolve again.

## API only (text in, text out)

When a key is set but no agent CLI can reach the vendor, the model can still read text and answer. It cannot read the repo or edit files, so use it only for a second opinion on a diff, a copy draft or a critique, with the content pasted into the request.

Both endpoints are OpenAI-compatible chat completions:

- OpenRouter: `https://openrouter.ai/api/v1/chat/completions` with `OPENROUTER_API_KEY`. Live model list: `GET https://openrouter.ai/api/v1/models/user`.
- xAI: `https://api.x.ai/v1/chat/completions` with `XAI_API_KEY`.

These calls are always billed per token: `consent check openrouter <model>` or `consent check api <model>` prints `ask` until the user has said yes to that model today ([usage.md](usage.md)).

Read the key from the environment inside the command. Never print it or write it to a file.
