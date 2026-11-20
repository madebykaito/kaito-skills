#!/bin/sh
# Print the model runners on this machine and the models each can reach.
# Reads only. Makes no network calls of its own and never prints a key.
# Optional filter: models-available.sh gemini

filter="${1:-.}"
has() { command -v "$1" >/dev/null 2>&1; }

echo "RUNNERS"
for c in claude codex gemini cursor-agent opencode copilot ollama; do
  if has "$c"; then echo "  $c: yes"; else echo "  $c: no"; fi
done

echo "API KEYS (presence only)"
for k in ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY XAI_API_KEY OPENROUTER_API_KEY; do
  eval "v=\${$k:-}"
  if [ -n "$v" ]; then echo "  $k: set"; else echo "  $k: unset"; fi
done

# The model lists come from the resolver, so both always agree.
node "$(dirname "$0")/kaito-models.mjs" list "$filter"
exit 0
