# Usage and cost

`U="node ~/.kaito/store/helpmekaito/scripts/kaito-usage.mjs"` below. `KAITO_HOME` replaces `~/.kaito` here as elsewhere. The script reads logs on this machine and makes no network calls.

## "How much have I used"

"kaito, how much have I used", "what did I spend", "show my token usage": run `$U report` (last 7 days) or `$U report <days>` when the user names a window. This skips routing.

Show the table as printed: one row per day and model with input, output, cache read and cache write tokens and the estimated price. Then relay, in your own words:

- The price is an estimate from list prices in [prices.json](prices.json), not a bill. On a subscription plan nothing is charged per token; the figure is what the same tokens would cost on the API.
- Every `not readable` line under `Runners:`, with its reason. Never drop one: a runner that could not be read means the totals are missing its usage.
- Every `No price for <model>` line. That model is left out of the total. Do not make up a price for it.
- The `Main model` and `Cheaper tiers` lines: which model had the most tokens in the window and how many tokens went to a cheaper tier instead. `tier split unavailable` means say so, not guess.

## What is read

| Runner | Source |
|---|---|
| Claude Code | `~/.claude/projects/**/*.jsonl` (`CLAUDE_CONFIG_DIR`), one count per response |
| Codex | `~/.codex/sessions/**/*.jsonl` (`CODEX_HOME`), growth of the session total per turn |
| opencode | `~/.local/share/opencode/opencode.db`, read-only, through `node:sqlite` or the `sqlite3` command |
| Gemini CLI | `~/.gemini/tmp/*/chats/session-*` (`GEMINI_CLI_HOME`) |
| Cursor | not readable: Cursor keeps no token counts on disk |

The script reads these logs itself and does not call `ccusage`: it covers only some of the runners, and the direct readers work with nothing installed.

## Limits of the estimate

- Where a vendor charges more for long prompts (noted per row in prices.json), the lower price is used.
- A cache price a vendor does not publish is charged at that model's input price.
- A day is a local calendar day.
- Prices change. `updated` in prices.json is the day they were read from each row's `source` page; fix a row there when a vendor changes it. Rows are tried in order and the first match wins, so a more specific family goes above a broader one.

## Asking before a pay-per-token route

Before handing work to another runner (step 4), run `$U consent check <runner> <model>`, with the runner as named in [runners.md](runners.md) (`claude`, `codex`, `cursor-agent`, `opencode`, `gemini`, `openrouter`, `api`, or `host` for a host subagent).

- `ok`: go on. Subscription routes, a logged-in CLI or a host subagent, always print `ok` and are never asked about.
- `ask`: the route is billed per token (OpenRouter, a direct API call, or a CLI running on an API key from the environment). Ask once, naming the model: "This runs <model> through <runner> and is billed per token. Go ahead?" On a yes run `$U consent yes <model>`; it holds for that model until the end of the day. On a no, do not make the call: stay in the host or offer a subscription route.
