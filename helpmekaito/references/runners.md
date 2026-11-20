# Runners

How to hand a task to a model. Run `scripts/models-available.sh` first and use exact model ids from its output.

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

Verified on 2026-11-16: `claude`, `codex` and `cursor-agent`. The `opencode` and `gemini` rows are from their docs. Run `<cli> --help` once before first use on a machine and correct the flags if they differ.

Notes:
- Do not pass flags that skip all permission checks (`--dangerously-skip-permissions`, `--force`, `--yolo`) unless the user asked for that.
- opencode reaches Anthropic, OpenAI, Google, xAI, OpenRouter and local models through one `provider/id` scheme. `opencode models <provider>` lists them. When it is installed, it is the simplest way to reach a vendor that has no CLI of its own.
- Cursor ids carry the effort level, for example `gemini-4-argon-high`.
- Long runs go in the background. Do not block the turn on a call that can take minutes.

## API only (text in, text out)

When a key is set but no agent CLI can reach the vendor, the model can still read text and answer. It cannot read the repo or edit files, so use it only for a second opinion on a diff, a copy draft or a critique, with the content pasted into the request.

Both endpoints are OpenAI-compatible chat completions:

- OpenRouter: `https://openrouter.ai/api/v1/chat/completions` with `OPENROUTER_API_KEY`. Live model list: `GET https://openrouter.ai/api/v1/models/user`.
- xAI: `https://api.x.ai/v1/chat/completions` with `XAI_API_KEY`.

These calls are always billed per token: `consent check openrouter <model>` or `consent check api <model>` prints `ask` until the user has said yes to that model today ([usage.md](usage.md)).

Read the key from the environment inside the command. Never print it or write it to a file.
