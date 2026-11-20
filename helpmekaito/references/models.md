# Models by tier

Snapshot: 2026-11-16. Model names change monthly. Treat this table as a hint about rank, and treat `scripts/models-available.sh` as the truth about what exists. If a name here is missing from the live list, pick the newest model of the same family and rank.

## Tiers

| Tier | The work | Anthropic | OpenAI | Gemini | xAI | Open-weight |
|---|---|---|---|---|---|---|
| Light | Bulk, mechanical, well-specified: fill templates, rename, extract, format. | haiku | luna | Gemini 4 Hydrogen, 3.8 Flash | Grok 4.3 | DeepSeek V4.1 Flash |
| Standard | Normal builds and edits from a clear plan. | sonnet | terra | Gemini 4 Hydrogen at high effort | Grok 4.6 | Qwen Max, Mistral Large 4 |
| Hard | Architecture, review, debugging, anything needing judgment. | opus | sol | Gemini 4 Argon | Grok 4.7 | Kimi K3.1 Pro |
| Frontier | Long, ambiguous, high-stakes work. | fable | astra | Gemini 4 Carbon | Grok 4.7 at max effort | none |

Many runners expose effort as a suffix (`-low`, `-high`, `-xhigh`, `-max`). Within a tier, raise effort before raising the tier.

Open-weight models are reached through OpenRouter or opencode. Ranks for Gemini 4, Grok and open-weight models come from third-party comparisons, not vendor pages.

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

- Skip any model whose listing says "NO ZDR" unless the user named it.
- Skip free tiers that train on inputs (Gemini's free tier does) for private code unless the user named it.
- Send a delegate only the files the task needs.

## Fallback

If the wanted tier is unavailable on every runner: use the nearest higher tier in the host. If there is none higher, use the host's best and say the tier was unavailable.
