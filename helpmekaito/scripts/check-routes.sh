#!/bin/sh
# Drift check: every skill folder is mapped in references/domains, and every
# skill named in a domain table row or a recipe step exists as a folder, either
# top-level, in a bundle, or a gstack sub-skill. Lists routed skills that are user-only
# (disable-model-invocation) or carry hooks. Run from anywhere. Exits 1 on drift.
here="$(cd "$(dirname "$0")/.." && pwd -P)"
store="$(dirname "$here")"
maps="$here/references/domains"
bad=0 uo= hk=
not_skills="metal-fx"  # backticked words in those rows that are not skills

catalog=$(node "$here/scripts/kaito-catalog.mjs" "$store") || exit 1
[ ! -f "$store/gstack/SKILL.md" ] || catalog="$catalog gstack"
rows=$(grep -h '^|' "$maps"/*.md)
for rel in $catalog; do
  n=${rel##*/}
  [ "$n" = "$(basename "$here")" ] && continue
  printf '%s\n' "$rows" | grep -qF "\`$n\`" || { echo "unmapped skill: $n"; bad=1; }
done

for n in $({ printf '%s\n' "$rows"; cat "$here/references/recipes.md" 2>/dev/null; } |
    grep -o '`/\{0,1\}[a-z][a-z0-9-]*`' | tr -d '`/' | sort -u); do
  case " $not_skills " in *" $n "*) continue ;; esac
  f="$store/gstack/$n/SKILL.md"
  for rel in $catalog; do
    if [ "${rel##*/}" = "$n" ]; then f="$store/$rel/SKILL.md"; break; fi
  done
  [ -f "$f" ] || { echo "mapped but missing: $n"; bad=1; continue; }
  fm=$(awk 'NR==1 && /^---/ {f=1; next} f && /^---/ {exit} f' "$f")
  echo "$fm" | grep -q '^disable-model-invocation: *true' && uo="$uo $n"
  echo "$fm" | grep -q '^hooks:' && hk="$hk $n"
done

[ -n "$uo" ] && echo "user-only:$uo"
[ -n "$hk" ] && echo "hooks:$hk"
[ $bad -eq 0 ] && echo "routes ok"
exit $bad
