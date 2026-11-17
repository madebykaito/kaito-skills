#!/bin/sh
# Read a repo's manifests, instruction files and local skills; keep a fingerprint in project memory.
# Usage: kaito-project.sh scan|changed|record [dir]
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
cmd=${1:-}
case "$cmd" in scan|changed|record) ;; *) echo "usage: kaito-project.sh scan|changed|record [dir]" >&2; exit 2 ;; esac
if [ -n "${2:-}" ]; then root=$(cd "$2" && pwd -P) || exit 1
else root=$(git rev-parse --show-toplevel 2>/dev/null || pwd); root=$(cd "$root" && pwd -P); fi

sha() { { shasum -a 256 2>/dev/null || sha256sum; } | cut -d' ' -f1; }

scan() {
  cd "$root"
  files=""  # files that feed the fingerprint
  printf "root=%s\nhead=%s\n" "$root" "$(git rev-parse HEAD 2>/dev/null || echo none)"
  for f in package.json pyproject.toml Cargo.toml go.mod Gemfile Makefile composer.json pom.xml build.gradle* deno.json \
      bun.lockb pnpm-lock.yaml yarn.lock package-lock.json; do
    [ -f "$f" ] || continue
    echo "manifest: $f"
    # ponytail: lockfiles are a package manager hint only, they change too often to fingerprint
    case "$f" in bun.lockb|pnpm-lock.yaml|yarn.lock|package-lock.json) ;; *) files="$files$f
" ;; esac
  done
  if [ -f package.json ]; then
    node -e 'try{const s=JSON.parse(require("fs").readFileSync("package.json","utf8")).scripts||{};
      for(const k of Object.keys(s).slice(0,15))console.log("script: "+k+": "+String(s[k]).replace(/\s+/g," ").slice(0,120))}catch{}' 2>/dev/null || :
  fi
  for f in AGENTS.md CLAUDE.md .cursorrules .github/copilot-instructions.md; do
    [ -f "$f" ] || continue
    echo "instructions: $f"; files="$files$f
"
  done
  for f in .claude/skills/*/SKILL.md .agents/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    files="$files$f
"
    d=${f%/SKILL.md}; d=${d##*/}
    # name and description from the frontmatter; a folded or literal description (> or |) continues on indented lines
    nd=$(awk '
      NR == 1 { if ($0 != "---") exit; next }
      $0 == "---" { exit }
      match($0, /^[A-Za-z_-]+:/) { cur = substr($0, 1, RLENGTH - 1); v = substr($0, RLENGTH + 1); sub(/^[ \t]+/, "", v)
        if (cur == "name") name = v; else if (cur == "description") desc = v; next }
      cur == "description" && /^[ \t]/ { t = $0; sub(/^[ \t]+/, "", t); desc = desc " " t }
      END { sub(/^[>|][-+]?[ \t]*/, "", desc); gsub(/^ +| +$/, "", desc)
        gsub(/^["\047]|["\047]$/, "", name); gsub(/^["\047]|["\047]$/, "", desc); print name "\t" desc }' "$f" | tr '\r' ' ')
    n=${nd%%"	"*}; ds=${nd#*"	"}
    [ -n "$n" ] || n=$d
    ds=$(printf %s "$ds" | tr '\t' ' ' | sed 's/  */ /g' | cut -c1-120)
    printf "local_skill: %s\t%s\t%s\n" "$n" "$f" "$ds"
  done
  # fp: hash of "<path> <content hash>" lines, uncommitted files included
  list=$(printf %s "$files" | grep -v '^$' | LC_ALL=C sort | while IFS= read -r f; do printf "%s %s\n" "$f" "$(sha < "$f")"; done || :)
  echo "fp=$(printf "%s\n" "$list" | sha)"
}

pfile() { (cd "$root" && sh "$here/kaito-mem.sh" where) | sed -n 's/^project_file=//p'; }

case "$cmd" in
  scan) scan ;;
  changed)
    old=$(sed -n 's/^brief_fp: *//p' "$(pfile)" 2>/dev/null | head -n1) || old=""
    if [ -z "$old" ]; then echo new
    elif [ "$old" = "$(scan | sed -n 's/^fp=//p')" ]; then echo same
    else echo changed; fi
    ;;
  record)
    out=$(scan)
    cd "$root"
    sh "$here/kaito-mem.sh" set brief_fp "$(printf "%s\n" "$out" | sed -n 's/^fp=//p')"
    printf "%s\n" "$out" | sed -n 's/^local_skill: //p' | sh "$here/kaito-mem.sh" local-skills
    ;;
esac
