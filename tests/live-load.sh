#!/bin/sh
# Live check, not part of run.sh: it costs a model call and needs the real install.
# A fresh Claude Code session must load helpmekaito, then load the routed skill
# through the Skill tool. The evals cannot show this; their sandbox has one skill.
out=$(cd "$(mktemp -d)" && claude -p "the shadows on these cards look muddy, fix them: <div class=card>Hi</div>" \
  --output-format stream-json --verbose --allowedTools Skill < /dev/null 2>/dev/null)
loaded=$(printf '%s\n' "$out" | grep -o '"skill":"[^"]*"' | cut -d'"' -f4 | tr '\n' ' ')
echo "skills loaded: ${loaded:-none}"
case "$loaded" in helpmekaito\ *beautiful-shadows*|helpmekaito\ *better-ui*) echo "live load ok" ;; *) echo "live load FAILED"; exit 1 ;; esac
