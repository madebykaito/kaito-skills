#!/bin/sh
# Keep codegraph indexes in $KAITO_HOME/codegraph, linked from each repo.
# Usage: kaito-codegraph.sh slug|init|adopt [path] | status
set -eu
KAITO_HOME="${KAITO_HOME:-$HOME/.kaito}"
CG="$KAITO_HOME/codegraph"
die() { echo "kaito-codegraph: $*" >&2; exit 1; }

cmd=${1:-}
p=$(cd "${2:-.}" && pwd -P) || exit 1
h=$(printf %s "$p" | { shasum 2>/dev/null || sha1sum; } | cut -c1-8)
s="${p##*/}-$h" d="$CG/$s" l="$p/.codegraph"
guard() { [ "$p" != / ] && [ "$p" != "$(cd "$HOME" && pwd -P)" ] || die "refusing $p, index a project folder"; }

case "$cmd" in
  slug) echo "$s" ;;
  init)
    guard
    newlink=0 newdir=0
    [ -d "$d" ] || newdir=1
    if [ -L "$l" ] && [ "$(readlink "$l")" = "$d" ]; then mkdir -p "$d"
    elif [ -e "$l" ] || [ -L "$l" ]; then die "$l already exists, run: kaito-codegraph.sh adopt $p"
    else newlink=1; mkdir -p "$d"; ln -s "$d" "$l"; fi
    echo "$p" > "$d/.kaito-path"
    (cd "$p" && codegraph init -y) || {
      # Leave no link behind that reads as "indexed" when the index was never built.
      # Only what this run made: an index that was already central is never deleted.
      if [ "$newlink" = 1 ] || [ "$newdir" = 1 ]; then rm -f "${l:?}"; fi
      if [ "$newdir" = 1 ]; then rm -rf "${CG:?}/${s:?}"; fi
      die "codegraph init failed in $p"
    }
    ;;
  adopt)
    guard
    [ -L "$l" ] && [ "$(readlink "$l")" = "$d" ] && { echo "already adopted: $s"; exit 0; }
    # An adopt cut off between the move and the link: the index is already central, relink it.
    if [ ! -e "$l" ] && [ ! -L "$l" ] && [ -d "$d" ]; then ln -s "$d" "$l"; echo "adopted: $s"; exit 0; fi
    [ -d "$l" ] && [ ! -L "$l" ] || die "no real .codegraph folder in $p"
    [ ! -e "$d" ] || die "$d already exists"
    mkdir -p "$CG"; mv "$l" "$d"; ln -s "$d" "$l"
    echo "$p" > "$d/.kaito-path"
    echo "adopted: $s"
    ;;
  status)
    for x in "$CG"/*/; do
      [ -d "$x" ] || continue
      x=${x%/}
      m=$(stat -c %y "$x" 2>/dev/null | cut -c1-10 || true)
      [ -n "$m" ] || m=$(stat -f %Sm -t %Y-%m-%d "$x")
      echo "${x##*/} $(cat "$x/.kaito-path" 2>/dev/null || echo -) $m"  # ponytail: dir mtime, not newest file
    done
    ;;
  *) echo "usage: kaito-codegraph.sh slug|init|adopt [path] | status" >&2; exit 2 ;;
esac
