#!/bin/sh
# Cross-project memory in $KAITO_HOME/memory.
# Usage: kaito-mem.sh dir | where | note global|project "<text>" | codegraph-decision yes|no
set -eu
here=$(dirname "$0")
K="${KAITO_HOME:-$HOME/.kaito}"
# memory.path in config moves the memory folder; default $K/memory. A missing helper means the default.
M=$(node "$here/kaito-json.mjs" get "$K/config.json" memory.path 2>/dev/null | tr -d '"') || M=""
case "$M" in "~") M=$HOME ;; "~/"*) M="$HOME/${M#"~/"}" ;; "") M="$K/memory" ;; esac
RO="memory is read-only here; to allow Codex writes run setup and answer yes to codexwrite"

g=1; p=$(git rev-parse --show-toplevel 2>/dev/null) || { g=0; p=$(pwd); }
p=$(cd "$p" && pwd -P)
s=$(sh "$here/kaito-codegraph.sh" slug "$p")
pf="$M/projects/$s.md"

mirror() {  # best effort, never changes our exit code; a real failure is shown, "disabled" is not
  [ -x "$here/kaito-obsidian.sh" ] || return 0
  for f in "$@"; do
    o=$("$here/kaito-obsidian.sh" push "$f" 2>/dev/null) || :
    case "$o" in ""|*"skipped: disabled") ;; *) echo "$o" >&2 ;; esac
  done
}
# One writer at a time. ponytail: a lock left by a killed run is taken over after 2s.
lock() {
  [ -w "$M" ] || return 1  # read-only memory: fail fast, the caller prints why
  i=0; until mkdir "$M/.lock" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -eq 20 ]; then rmdir "$M/.lock" 2>/dev/null || :; fi  # take over a lock a killed run left
    [ "$i" -le 21 ] || return 1
    sleep 0.1
  done
  trap 'rmdir "$M/.lock" 2>/dev/null || :' EXIT  # set only once the lock is ours
}

case "${1:-}" in
  dir) echo "$M" ;;
  where)
    if [ "$g" = 0 ] || [ "$p" = / ] || [ "$p" = "$(cd "$HOME" && pwd -P)" ]; then i=n/a
    elif [ -e "$p/.codegraph" ]; then i=yes; else i=no; fi  # a dangling link is not an index
    out=$(printf "%s\n" "slug=$s" "project_file=$pf" "indexed=$i"
      cat "$pf" "$M/global.md" "$M/MEMORY.md" 2>/dev/null || :)  # project facts first: they survive the cut
    if [ "$(printf "%s\n" "$out" | wc -l)" -gt 40 ]; then printf "%s\n" "$out" | head -39; echo ...; else printf "%s\n" "$out"; fi
    ;;
  note)
    [ $# -eq 3 ] || { echo "usage: kaito-mem.sh note global|project \"<text>\"" >&2; exit 2; }
    # A narrow check, not a guarantee: it catches "token: x", "password is x", "Bearer x".
    printf %s "$3" | grep -Eiq '((api[_ -]?key|token|passw(or)?d|secret)[[:space:]]*(:|=|is[[:space:]])|bearer[[:space:]]+[a-z0-9._-]{12,})' &&
      { echo "kaito-mem: refusing to store what looks like a secret" >&2; exit 2; }
    t=$(printf %s "$3" | tr '\n\r' '  ')  # one note, one line: no injected lines
    case "$2" in global) f=global.md ;; project) f=projects/$s.md ;; *) exit 2 ;; esac
    (
      mkdir -p "$M/projects"; lock
      if [ "$2" = project ] && [ ! -e "$pf" ]; then
        printf "%s\n" "- projects/$s.md $p" >> "$M/MEMORY.md"
      fi
      printf "%s\n" "- $(date +%Y-%m-%d) $t" >> "$M/$f"
    ) 2>/dev/null || { echo "$RO"; exit 0; }
    mirror "$f" MEMORY.md
    ;;
  codegraph-decision)
    case "${2:-}" in yes|no) ;; *) echo "usage: kaito-mem.sh codegraph-decision yes|no" >&2; exit 2 ;; esac
    (
      mkdir -p "$M/projects"; lock
      [ -e "$pf" ] || printf "%s\n" "- projects/$s.md $p" >> "$M/MEMORY.md"
      { grep -v '^codegraph:' "$pf" 2>/dev/null || :; echo "codegraph: $2"; } > "$pf.$$.tmp"
      mv "$pf.$$.tmp" "$pf"
    ) 2>/dev/null || { echo "$RO"; exit 0; }
    mirror "projects/$s.md" MEMORY.md
    ;;
  *) echo "usage: kaito-mem.sh dir | where | note global|project \"<text>\" | codegraph-decision yes|no" >&2; exit 2 ;;
esac
