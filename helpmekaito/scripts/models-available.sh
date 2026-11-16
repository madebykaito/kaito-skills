#!/bin/sh
# Print the model runners on this machine and the models each can reach.
# Reads only. Makes no network calls of its own and never prints a key.
# Optional filter: models-available.sh gemini

filter="${1:-.}"
show() { grep -iE "$filter" | head -80 | sed 's/^/  /'; }
has() { command -v "$1" >/dev/null 2>&1; }

echo "RUNNERS"
for c in claude codex cursor-agent opencode gemini; do
  if has "$c"; then echo "  $c: yes"; else echo "  $c: no"; fi
done

echo "API KEYS (presence only)"
for k in ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY GOOGLE_API_KEY XAI_API_KEY OPENROUTER_API_KEY; do
  eval "v=\${$k:-}"
  if [ -n "$v" ]; then echo "  $k: set"; else echo "  $k: unset"; fi
done

if has claude; then
  echo "MODELS claude (aliases)"
  printf 'haiku\nsonnet\nopus\nfable\n' | show
fi

cache="${CODEX_HOME:-$HOME/.codex}/models_cache.json"
if has codex && [ -f "$cache" ]; then
  echo "MODELS codex"
  grep -oE '"slug": *"[^"]+"' "$cache" | sed 's/.*: *"\(.*\)"/\1/' | sort -u | show
fi

if has cursor-agent; then
  echo "MODELS cursor-agent"
  cursor-agent --list-models 2>/dev/null | grep ' - ' | show
fi

if has opencode; then
  echo "MODELS opencode"
  opencode models 2>/dev/null | show
fi
exit 0
