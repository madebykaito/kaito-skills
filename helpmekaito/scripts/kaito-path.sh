#!/bin/sh
# kaito-path.sh <skill> [--host claude|codex]
# Prints the SKILL.md path for a skill in the kaito store.
# Exit 1: not found. Exit 3: user-only (disable-model-invocation), tell the
# user to type /<skill> (in Claude Code: no other host has the command). Exit 4: has hooks and host is codex, needs Claude.
# The path is printed on exit 3 and 4 too.
n="$1"; host=claude
[ "$2" = --host ] && host="$3"
case "$n" in ''|*/*|.*) echo "usage: kaito-path.sh <skill> [--host claude|codex]" >&2; exit 1;; esac
S="${KAITO_HOME:-$HOME/.kaito}/store"
b="${n#gstack-}"
p=

# $S/gstack is the gstack build folder, not a skill.
[ "$n" != gstack ] && [ -f "$S/$n/SKILL.md" ] && p="$S/$n/SKILL.md"
if [ -z "${p:-}" ]; then
  here=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
  rel=$(node "$here/kaito-catalog.mjs" "$S" "$n") || exit 1
  [ -z "$rel" ] || p="$S/$rel/SKILL.md"
fi
if [ -z "${p:-}" ]; then
  if [ "$host" = codex ]; then set -- "$S/_gstack-codex/.agents/skills/gstack-$b" "$S/_gstack-codex/.agents/skills/$n"
  elif [ "$n" = gstack ]; then set -- "$S/_gstack-claude"
  else set -- "$S/_gstack-claude/$n" "$S/_gstack-claude/$b"; fi
  for d; do [ -f "$d/SKILL.md" ] && { p="$d/SKILL.md"; break; }; done
fi
[ -n "${p:-}" ] || exit 1
echo "$p"

# The Codex render keeps only name and description, so read gstack flags from
# the source copy in $S/gstack, else the Claude render.
f="$p"
case "$p" in "$S"/_gstack-*)
  for d in "$S/gstack/$n" "$S/gstack/$b" "$S/_gstack-claude/$n" "$S/_gstack-claude/$b"; do
    [ -f "$d/SKILL.md" ] && { f="$d/SKILL.md"; break; }
  done;;
esac
fm=$(awk 'NR==1 && /^---/ {f=1; next} f && /^---/ {exit} f' "$f")
echo "$fm" | grep -q '^disable-model-invocation: *true' && { echo user-only >&2; exit 3; }
[ "$host" = codex ] && echo "$fm" | grep -q '^hooks:' && { echo hooks >&2; exit 4; }
exit 0
