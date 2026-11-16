#!/bin/sh
# Drift check: every skill folder is mapped in references/domains, and every
# skill named in the first column of a domain table exists as a folder, either
# top-level or a gstack sub-skill. Lists routed skills that are user-only
# (disable-model-invocation) or carry hooks. Run from anywhere. Exits 1 on drift.
here="$(cd "$(dirname "$0")/.." && pwd -P)"
store="$(dirname "$here")"
maps="$here/references/domains"
bad=0 uo= hk=

for d in "$store"/*/; do
  n=$(basename "$d")
  [ -f "$d/SKILL.md" ] || continue
  [ "$n" = "$(basename "$here")" ] && continue
  grep -qF "\`$n\`" "$maps"/*.md || { echo "unmapped skill: $n"; bad=1; }
done

for n in $(sed -n 's/^| `\([a-z0-9-]*\)`.*/\1/p' "$maps"/*.md | sort -u); do
  f="$store/$n/SKILL.md"; [ -f "$f" ] || f="$store/gstack/$n/SKILL.md"
  [ -f "$f" ] || { echo "mapped but missing: $n"; bad=1; continue; }
  fm=$(awk 'NR==1 && /^---/ {f=1; next} f && /^---/ {exit} f' "$f")
  echo "$fm" | grep -q '^disable-model-invocation: *true' && uo="$uo $n"
  echo "$fm" | grep -q '^hooks:' && hk="$hk $n"
done

[ -n "$uo" ] && echo "user-only:$uo"
[ -n "$hk" ] && echo "hooks:$hk"
[ $bad -eq 0 ] && echo "routes ok"
exit $bad
