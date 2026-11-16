#!/bin/sh
# Drift check: every skill folder is mapped in references/domains, and every
# skill named in the first column of a domain table exists as a folder.
# Run from anywhere. Exits 1 on drift.
here="$(cd "$(dirname "$0")/.." && pwd -P)"
store="$(dirname "$here")"
maps="$here/references/domains"
bad=0

for d in "$store"/*/; do
  n=$(basename "$d")
  [ -f "$d/SKILL.md" ] || continue
  [ "$n" = "$(basename "$here")" ] && continue
  grep -qF "\`$n\`" "$maps"/*.md || { echo "unmapped skill: $n"; bad=1; }
done

for n in $(sed -n 's/^| `\([a-z0-9-]*\)`.*/\1/p' "$maps"/*.md | sort -u); do
  [ -f "$store/$n/SKILL.md" ] || { echo "mapped but missing: $n"; bad=1; }
done

[ $bad -eq 0 ] && echo "routes ok"
exit $bad
