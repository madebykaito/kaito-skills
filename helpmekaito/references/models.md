# Models by tier

No model versions are listed here. A model's tier comes from the family word in its id, and `scripts/kaito-models.mjs` picks the newest model of that family this machine can reach. A new release needs no change to this file.

## Tiers

| Tier | The work | Family word in the id |
|---|---|---|
| Light | Bulk, mechanical, well-specified: fill templates, rename, extract, format. | `haiku`, `luna`, `hydrogen`, and any id with `lite`, `mini` or `nano` (so `flash-lite`) |
| Standard | Normal builds and edits from a clear plan. | `sonnet`, `terra`, `flash` |
| Hard | Architecture, review, debugging, anything needing judgment. | `opus`, `sol`, `pro`, `argon` |
| Frontier | Long, ambiguous, high-stakes work. | `fable`, `astra`, `ultra`, `carbon` |

The rule lives in `tierOf` in `scripts/kaito-models.mjs`. When a vendor adds a family, add its word there and here.

## Picking the model

```
node scripts/kaito-models.mjs resolve <vendor-or-runner> <light|standard|hard|frontier>
```

- A vendor (`anthropic`, `openai`, `google`, `xai`, or the first word of an id such as `kimi`) looks across every agent CLI on the machine and prints one line: `<runner> <model-id>`.
- A runner (`claude`, `codex`, `gemini`, `cursor-agent`, `opencode`, `copilot`, `ollama`) looks only there, and prints one line per vendor it reaches.
- Newest is the highest version number in the id. At the same version a released model beats a preview. An alias such as `opus` counts as newest.
- A line that starts with `host:` means nothing fits, and says why. Do the work on the host's model and tell the user that line.
- Ids with no family word (Grok, most open-weight models, plain `gpt-5.5`) cannot be placed, so they are never picked. Use one only when the user names it.
- `node scripts/kaito-models.mjs tier <model-id>` prints the tier of one id.

If a run fails because the model is unavailable, out of quota or refused, run `node scripts/kaito-models.mjs fail <runner> <model-id>` and resolve again. That model is skipped on that runner for the rest of the day.

The agent CLIs found are stored in `~/.kaito/agents.json`. Setup writes it, `./setup --upgrade` refreshes it, and it is found again when it is a day old. `node scripts/kaito-models.mjs detect` refreshes it now.

Many runners expose effort as a suffix (`-low`, `-high`, `-xhigh`, `-max`). The resolver returns the plain or medium id. Within a tier, raise effort before raising the tier.

## Sizing the task

Size the delegated piece, not the whole request.

- **Trivial**: a factual answer or a one-line edit. No skill, no delegation.
- **Light**: the output is fully determined by the input and a template. A wrong answer is obvious and cheap to redo.
- **Standard**: there is a plan and the work is carrying it out.
- **Hard**: the plan itself is the work, or a mistake would be subtle.
- **Frontier**: many hours, unclear goal, or a mistake would be expensive.

When unsure between two tiers, take the higher one. A weak model on a hard task costs more in rework than the price difference.

## What stays in the main session

- Taste: visual design, copy voice, the final call on a review. The user chose this session's model for those.
- Anything that needs the conversation so far. A delegate starts with only its brief.
- Small work. Delegation has a fixed cost: writing the brief and checking the result.

## When to delegate, and where

Delegate inside the host first (its own subagents). Go to another vendor's CLI when:

1. The user names a model or vendor. Use it. If it is not available, say so and stop. Never substitute silently.
2. A review wants a second opinion. Pick a different vendor than the one that wrote the code, at hard tier.
3. The work is bulk and a light tier elsewhere is clearly cheaper or faster than the host's lightest.
4. The task needs a tier the host cannot reach.

Before any cross-vendor call, say in one line which model, which runner and why. The call spends that vendor's quota, so the user should see it happen.

A route billed per token (OpenRouter, a direct API call, or a CLI running on an API key) also needs a yes first: run the consent check in [usage.md](usage.md). It asks once per model per day. Subscription routes are never asked about.

## Privacy

- Skip any model whose listing says "NO ZDR" unless the user named it. The resolver never picks one.
- Skip free tiers that train on inputs (Gemini's free tier does) for private code unless the user named it. The resolver never picks an id marked `free`.
- Send a delegate only the files the task needs.

## Fallback

If the wanted tier is unavailable on every runner: use the nearest higher tier in the host. If there is none higher, use the host's best and say the tier was unavailable.
