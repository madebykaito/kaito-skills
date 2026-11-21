#!/bin/sh
# Cross-project memory in $KAITO_HOME/memory.
# Usage: kaito-mem.sh dir | where | note global|project "<text>" | codegraph-decision yes|no
#        | set board|brief_fp "<value>" | local-skills (name<TAB>path<TAB>desc lines on stdin)
#        | learn correction|preference|worked|failed|convention "<text>" [global]
#        | capture correction|preference|worked|failed|convention [global] (one lesson on stdin)
#        | forget "<text>" [global|project] | promote "<text>" [global|project] | curate | stats      (see references/learning.md)
set -eu
here=$(dirname "$0")
K="${KAITO_HOME:-$HOME/.kaito}"
# memory.path in config moves the memory folder; default $K/memory. A missing helper means the default.
M=$(node "$here/kaito-json.mjs" get "$K/config.json" memory.path 2>/dev/null | tr -d '"') || M=""
case "$M" in "~") M=$HOME ;; "~/"*) M="$HOME/${M#"~/"}" ;; "") M="$K/memory" ;; esac
RO="memory is read-only here; to allow Codex writes run setup and answer yes to codexwrite"
. "$here/kaito-memory-lock.sh"

g=1; p=$(git rev-parse --show-toplevel 2>/dev/null) || { g=0; p=$(pwd); }
p=$(cd "$p" && pwd -P)
s=$(sh "$here/kaito-codegraph.sh" slug "$p")
pf="$M/projects/$s.md"

mirror() {  # best effort, never changes our exit code; a real failure is shown, "disabled" is not
  [ -x "$here/kaito-obsidian.sh" ] || return 0
  for f in "$@"; do
    o=$("$here/kaito-obsidian.sh" push "$f" 2>/dev/null) || :
    case "$o" in ""|*"skipped: disabled"|*"skipped: memory is inside the vault") ;; *) echo "$o" >&2 ;; esac
  done
}
# A narrow check, not a guarantee: it catches "token: x", "password is x", "Bearer x".
nosecret() {
  printf %s "$1" | grep -Eiq '((api[_ -]?key|token|passw(or)?d|secret)[[:space:]]*(:|=|is[[:space:]])|bearer[[:space:]]+[a-z0-9._+/=-]{12,})' &&
    { echo "kaito-mem: refusing to store what looks like a secret" >&2; exit 2; }
  return 0
}
# put <key> <lines>: replace every "<key>:" line of the project file with <lines>.
put() {
  (
    mkdir -p "$M/projects" || exit 1
    memory_lock "$M" || exit $?
    [ -e "$pf" ] || printf "%s\n" "- projects/$s.md $p" >> "$M/MEMORY.md"
    { grep -v "^$1:" "$pf" 2>/dev/null || :; [ -z "$2" ] || printf "%s\n" "$2"; } > "$pf.$$.tmp"
    mv "$pf.$$.tmp" "$pf"
  ) 2>/dev/null || wfail $?
  mirror "projects/$s.md" MEMORY.md
}

# Learnings: "learn: <kind> <count> <last date> <text>" lines in the project file and global.md.
today=${KAITO_TODAY:-$(date +%Y-%m-%d)}  # KAITO_TODAY: tests and backfills
case "$today" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) echo "kaito-mem: KAITO_TODAY must be YYYY-MM-DD" >&2; exit 2 ;; esac
LEARN_CAP=10  # learnings printed by where
# Shared awk: txt() is a learn line's text, days() is a day number. norm() is the key two texts are compared by:
# lower case, punctuation and spacing folded, but + and # kept and a dot kept inside a word (C++, C#, .NET, Node.js).
# The punctuation set is a string, not a /regex/: busybox awk keeps the backslash of "\/" inside a bracket,
# which turned "!-\/" into a range that swallowed digits.
AWKLIB='function txt(l) { sub("\r$", "", l); sub(/^learn:[ \t]+[a-z]+[ \t]+[0-9]+[ \t]+[0-9-]+[ \t]+/, "", l); return l }
function norm(x) { x = tolower(x); gsub("[ \t\r!\"$-*,/:-@[-`{-~-]+", " ", x); gsub(/\.+ /, " ", x); sub(/\.+$/, "", x)
  gsub(/  +/, " ", x); sub(/^ /, "", x); sub(/ $/, "", x); return x }
function days(s,  y, m, d) { y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
  if (m < 3) { y--; m += 12 }
  return 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + d }'
# Token shapes on top of nosecret: vendor key prefixes, PEM blocks, JWTs, and any 32+ character run with letters and digits.
nokey() {
  if printf %s "$1" | grep -Eq '(sk-[A-Za-z0-9_-]{16,}|glpat-[A-Za-z0-9_-]{10,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|-----BEGIN|eyJ[A-Za-z0-9_-]{10,}\.)' ||
     printf %s "$1" | grep -Eo '[A-Za-z0-9_+=-]{32,}' | grep '[0-9]' | grep -q '[A-Za-z]'; then
    echo "kaito-mem: refusing to store what looks like a secret" >&2; exit 2
  fi
}
# rewrite <file> <awk args>: call inside a locked subshell. The file is replaced only when it was read and awk
# exited 0. awk exit 4 ("no match") is passed on; any other failure is exit 3. Either way the file stays as it was.
rewrite() {
  rf="$M/$1"; shift
  [ -r "$rf" ] || exit 3
  rc=0; LC_ALL=C awk "$@" "$rf" > "$rf.$$.tmp" || rc=$?
  [ "$rc" = 0 ] && mv "$rf.$$.tmp" "$rf" && return 0
  rm -f "$rf.$$.tmp"; [ "$rc" != 4 ] || exit 4; exit 3
}
# wfail <status of a write subshell>: 3 is a failed rewrite, 74 a busy lock, anything else is memory we may not write.
wfail() {
  case "$1" in 74) echo "kaito-mem: memory is busy; nothing was saved" >&2; exit 74 ;; 3) echo "kaito-mem: could not rewrite the memory file; nothing was changed" >&2; exit 1 ;; *) echo "$RO"; exit 0 ;; esac
}
# relearn forget|promote "<text>" [global|project]: drop the matching learning, or turn it into a "rule:" line.
# Without a scope: the project file first, then global.
relearn() {
  case "${3:-}" in ""|global|project) ;; *) set -- "$1" "" ;; esac
  [ -n "$2" ] || { echo "usage: kaito-mem.sh $1 \"<text>\" [global|project]" >&2; exit 2; }
  for f in "projects/$s.md" global.md; do
    case "${3:-}:$f" in project:global.md|global:projects/*) continue ;; esac
    [ -f "$M/$f" ] || continue
    rc=0
    (
      memory_lock "$M" || exit $?
      T=$2; export T
      rewrite "$f" -v mode="$1" "$AWKLIB"'
        BEGIN { n = norm(ENVIRON["T"]) }
        !hit && /^learn:/ && norm(txt($0)) == n { hit = 1; if (mode == "promote") print "rule: " txt($0); next }
        { print }
        END { exit hit ? 0 : 4 }'
    ) 2>/dev/null || rc=$?
    case "$rc" in 0) mirror "$f"; return 0 ;; 4) ;; *) wfail "$rc" ;; esac
  done
  echo "kaito-mem: no such learning; copy its text from kaito-mem.sh curate" >&2; exit 1
}
# Each file ends its own last line, and a CR from a Windows editor is dropped.
learnings() {
  for lf in "$pf" "$M/global.md"; do [ ! -r "$lf" ] || awk 1 "$lf"; done 2>/dev/null | tr -d '\r' | grep '^learn:' || :
}

case "${1:-}" in
  dir) echo "$M" ;;
  where)
    if [ "$g" = 0 ] || [ "$p" = / ] || [ "$p" = "$(cd "$HOME" && pwd -P)" ]; then i=n/a
    elif [ -e "$p/.codegraph" ]; then i=yes; else i=no; fi  # a dangling link is not an index
    # top is never cut: keyed lines, rules, then the most confirmed, most recent learnings of this project and user
    L=$(learnings | sort -k3,3nr -k4,4r); n=$(printf "%s\n" "$L" | grep -c . || :)
    top=$(printf "%s\n" "slug=$s" "project_file=$pf" "indexed=$i"
      { grep -E '^(tracker|tracking|board|local_skill|rule):' "$pf" || :; grep '^rule:' "$M/global.md" || :
        [ "$n" -eq 0 ] || printf "%s\n" "$L" | head -n "$LEARN_CAP"
        [ "$n" -le "$LEARN_CAP" ] || echo "learn_more: $((n - LEARN_CAP)) not shown; run kaito-mem.sh curate"; } 2>/dev/null)
    rest=$({ grep -vE '^(tracker|tracking|board|local_skill|rule|learn):' "$pf" || :
      grep -vE '^(rule|learn):' "$M/global.md" || :; cat "$M/MEMORY.md" || :; } 2>/dev/null)  # project facts first: they survive the cut
    printf "%s\n" "$top"
    room=$((40 - $(printf "%s\n" "$top" | wc -l))); nr=0; [ -z "$rest" ] || nr=$(printf "%s\n" "$rest" | wc -l)
    if [ "$nr" -le "$room" ]; then [ "$nr" -eq 0 ] || printf "%s\n" "$rest"
    else [ "$room" -le 1 ] || printf "%s\n" "$rest" | head -n $((room - 1)); echo ...; fi
    ;;
  note)
    [ $# -eq 3 ] || { echo "usage: kaito-mem.sh note global|project \"<text>\"" >&2; exit 2; }
    nosecret "$3"
    t=$(printf %s "$3" | tr '\n\r' '  ')  # one note, one line: no injected lines
    case "$2" in global) f=global.md ;; project) f=projects/$s.md ;; *) exit 2 ;; esac
    (
      mkdir -p "$M/projects" || exit 1
      memory_lock "$M" || exit $?
      if [ "$2" = project ] && [ ! -e "$pf" ]; then
        printf "%s\n" "- projects/$s.md $p" >> "$M/MEMORY.md"
      fi
      printf "%s\n" "- $(date +%Y-%m-%d) $t" >> "$M/$f"
    ) 2>/dev/null || wfail $?
    mirror "$f" MEMORY.md
    ;;
  codegraph-decision)
    case "${2:-}" in yes|no) ;; *) echo "usage: kaito-mem.sh codegraph-decision yes|no" >&2; exit 2 ;; esac
    put codegraph "codegraph: $2"
    ;;
  set)
    case "${2:-}" in board|brief_fp) [ $# -eq 3 ] || exit 2 ;; *) echo "usage: kaito-mem.sh set board|brief_fp \"<value>\"" >&2; exit 2 ;; esac
    nosecret "$3"
    put "$2" "$2: $(printf %s "$3" | tr '\n\r' '  ')"
    ;;
  local-skills)
    in=$(tr -d '\r' | grep -v '^[[:space:]]*$' || :)
    nosecret "$in"
    put local_skill "$(printf "%s\n" "$in" | grep -v '^$' | tr '\t' ' ' | sed 's/^/local_skill: /' || :)"
    ;;
  learn)
    ok=1; t=$(printf %s "${3:-}" | tr '\n\r' '  ')
    case "${2:-}" in correction|preference|worked|failed|convention) ;; *) ok=0 ;; esac
    case "${4:-project}" in project) f=projects/$s.md ;; global) f=global.md ;; *) ok=0 ;; esac
    [ "$ok" = 1 ] && [ -n "$(printf %s "$t" | tr -d ' ')" ] ||
      { echo "usage: kaito-mem.sh learn correction|preference|worked|failed|convention \"<text>\" [global]" >&2; exit 2; }
    nosecret "$t"; nokey "$t"
    (
      mkdir -p "$M/projects" || exit 1
      memory_lock "$M" || exit $?
      new=0; [ "$f" = global.md ] || [ -e "$pf" ] || new=1
      [ -e "$M/$f" ] || : > "$M/$f" || exit 3
      T=$t; export T
      # the same text again, whatever the kind, confirms the learning: count up, date to today
      rewrite "$f" -v k="$2" -v d="$today" "$AWKLIB"'
        BEGIN { t = ENVIRON["T"]; n = norm(t) }
        !hit && /^learn:/ && norm(txt($0)) == n { hit = 1; print "learn: " $2 " " $3 + 1 " " d " " txt($0); next }
        { print }
        END { if (!hit) print "learn: " k " 1 " d " " t }'
      # only a learning that is on disk is indexed and logged
      [ "$new" = 0 ] || printf "%s\n" "- projects/$s.md $p" >> "$M/MEMORY.md" || :
      printf "%s\n" "$today $s $2" >> "$M/learning.log" || :  # one line per capture: what stats counts
    ) 2>/dev/null || wfail $?
    mirror "$f" MEMORY.md
    ;;
  capture)
    ok=1; t=$(tr '\n\r' '  ' | sed 's/[[:space:]]*$//')
    case "${2:-}" in correction|preference|worked|failed|convention) ;; *) ok=0 ;; esac
    case "${3:-project}" in project) f=projects/$s.md ;; global) f=global.md ;; *) ok=0 ;; esac
    case "${3:-project}:${2:-}" in global:correction|global:preference|project:*) ;; *) ok=0 ;; esac
    [ "$ok" = 1 ] && [ -n "$(printf %s "$t" | tr -d ' ')" ] ||
      { echo "usage: kaito-mem.sh capture correction|preference|worked|failed|convention [global] < lesson" >&2; exit 2; }
    nosecret "$t"; nokey "$t"
    rc=0
    (
      mkdir -p "$M/projects" || exit 73
      memory_lock "$M" || exit $?
      new=0; [ "$f" = global.md ] || [ -e "$pf" ] || new=1
      T=$t; export T
      w=0
      if [ -e "$M/$f" ]; then
        rewrite "$f" -v k="$2" -v d="$today" "$AWKLIB"' \
          BEGIN { t = ENVIRON["T"]; n = norm(t) }
          /^learn:/ && norm(txt($0)) == n { hit = 1 }
          { print }
          END { if (!hit) print "learn: " k " 1 " d " " t; exit hit ? 4 : 0 }' || w=$?
      else
        printf '%s\n' "learn: $2 1 $today $t" > "$M/$f.$$.tmp" || exit 1
        mv "$M/$f.$$.tmp" "$M/$f" || { rm -f "$M/$f.$$.tmp"; exit 1; }
      fi
      [ "$w" = 4 ] && exit 4
      [ "$w" = 0 ] || exit 1
      LC_ALL=C awk "$AWKLIB"'
        BEGIN { n = norm(ENVIRON["T"]) }
        /^learn:/ && norm(txt($0)) == n { found = 1 }
        END { exit found ? 0 : 1 }' "$M/$f" || exit 1
      [ "$new" = 0 ] || printf "%s\n" "- projects/$s.md $p" >> "$M/MEMORY.md" || echo "kaito-mem: warning: the project index was not updated" >&2
      printf "%s\n" "$today $s $2" >> "$M/learning.log" || echo "kaito-mem: warning: the learning log was not updated" >&2
    ) || rc=$?
    case "$rc" in
      0) mirror "$f" MEMORY.md; echo saved ;;
      4) echo already_present ;;
      73) echo "$RO" >&2; exit 73 ;;
      74) echo "kaito-mem: memory is busy; capture was not saved" >&2; exit 74 ;;
      *) echo "kaito-mem: could not write the memory file; capture was not saved" >&2; exit 1 ;;
    esac
    ;;
  forget|promote) relearn "$1" "${2:-}" "${3:-}" ;;
  curate)
    learnings | LC_ALL=C awk -v today="$today" "$AWKLIB"'
      { n++; line[n] = $2 " " $3 "x " $4 " " txt($0); t[n] = norm(txt($0)); c[n] = $3 + 0; age[n] = days(today) - days($4) }
      END {
        print "learnings: " n + 0
        for (i = 1; i <= n; i++) {
          split("", a); nw = split(t[i], w, " "); for (k = 1; k <= nw; k++) a[w[k]] = 1
          na = 0; for (k in a) na++
          for (j = i + 1; j <= n; j++) {  # near: at least 60% of the distinct words are shared
            split("", b); nw = split(t[j], w, " "); for (k = 1; k <= nw; k++) b[w[k]] = 1
            nb = 0; both = 0; for (k in b) { nb++; if (k in a) both++ }
            if (t[i] == t[j] || both >= 0.6 * (na + nb - both)) { print "duplicate: " line[i] " || " line[j]; found = 1 }
          }
        }
        for (i = 1; i <= n; i++) if (age[i] >= 30) { print "stale: " line[i]; found = 1 }
        for (i = 1; i <= n; i++) if (c[i] >= 3) { print "promote: " line[i]; found = 1 }
        if (!found) print "nothing to curate"
      }'
    ;;
  stats)
    echo "corrections per week, oldest first; the last week ends $today"
    { echo "$today $s -"; cat "$M/learning.log" 2>/dev/null || :; } | LC_ALL=C awk -v today="$today" "$AWKLIB"'
      NF >= 3 { p = $0; sub(/^[^ ]+ /, "", p); sub(/ [^ ]+$/, "", p)  # date first, kind last: a slug may hold spaces
        seen[p] = 1; a = days(today) - days($1); if ($NF == "correction" && a >= 0 && a < 28) c[p, 3 - int(a / 7)]++ }
      END { for (p in seen) print p ": " c[p, 0] + 0 " " c[p, 1] + 0 " " c[p, 2] + 0 " " c[p, 3] + 0 }' | sort
    ;;
  *) echo "usage: kaito-mem.sh dir | where | note global|project \"<text>\" | codegraph-decision yes|no | set board|brief_fp \"<value>\" | local-skills | learn <kind> \"<text>\" [global] | capture <kind> [global] < lesson | forget|promote \"<text>\" [global|project] | curate | stats" >&2; exit 2 ;;
esac
