#!/bin/sh
# Cross-project memory in $KAITO_HOME/memory.
# Usage: kaito-mem.sh where | note global|project "<text>" | codegraph-decision yes|no
set -eu
here=$(dirname "$0")
M="${KAITO_HOME:-$HOME/.kaito}/memory"
RO="memory is read-only here; to allow Codex writes run setup and answer yes to codexwrite"

p=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
p=$(cd "$p" && pwd -P)
s=$(sh "$here/kaito-codegraph.sh" slug "$p")
pf="$M/projects/$s.md"

mirror() {  # best effort, never changes our exit code
  [ -x "$here/kaito-obsidian.sh" ] || return 0
  for f in "$@"; do "$here/kaito-obsidian.sh" push "$f" >/dev/null 2>&1 || :; done
}

case "${1:-}" in
  where)
    if [ "$p" = / ] || [ "$p" = "$(cd "$HOME" && pwd -P)" ]; then i=n/a
    elif [ -e "$p/.codegraph" ] || [ -L "$p/.codegraph" ]; then i=yes; else i=no; fi
    out=$(printf "%s\n" "slug=$s" "project_file=$pf" "indexed=$i"
      cat "$M/MEMORY.md" "$pf" 2>/dev/null || :)
    if [ "$(printf "%s\n" "$out" | wc -l)" -gt 40 ]; then printf "%s\n" "$out" | head -39; echo ...; else printf "%s\n" "$out"; fi
    ;;
  note)
    [ $# -eq 3 ] || { echo "usage: kaito-mem.sh note global|project \"<text>\"" >&2; exit 2; }
    printf %s "$3" | grep -Eiq '(api[_-]?key|token|password|secret)[[:space:]]*[:=]' &&
      { echo "kaito-mem: refusing to store what looks like a secret" >&2; exit 2; }
    case "$2" in global) f=global.md ;; project) f=projects/$s.md ;; *) exit 2 ;; esac
    (
      mkdir -p "$M/projects"
      if [ "$2" = project ] && [ ! -e "$pf" ]; then
        printf "%s\n" "- projects/$s.md $p" >> "$M/MEMORY.md"
      fi
      printf "%s\n" "- $(date +%Y-%m-%d) $3" >> "$M/$f"
    ) 2>/dev/null || { echo "$RO"; exit 0; }
    mirror "$f" MEMORY.md
    ;;
  codegraph-decision)
    case "${2:-}" in yes|no) ;; *) echo "usage: kaito-mem.sh codegraph-decision yes|no" >&2; exit 2 ;; esac
    (
      mkdir -p "$M/projects"
      [ -e "$pf" ] || printf "%s\n" "- projects/$s.md $p" >> "$M/MEMORY.md"
      { grep -v '^codegraph:' "$pf" 2>/dev/null || :; echo "codegraph: $2"; } > "$pf.tmp"
      mv "$pf.tmp" "$pf"
    ) 2>/dev/null || { echo "$RO"; exit 0; }
    mirror "projects/$s.md" MEMORY.md
    ;;
  *) echo "usage: kaito-mem.sh where | note global|project \"<text>\" | codegraph-decision yes|no" >&2; exit 2 ;;
esac
