#!/bin/sh
# Cross-project memory in $KAITO_HOME/memory.
# Usage: kaito-mem.sh dir | slug | label | where [task] | note global|project "<text>" | codegraph-decision yes|no
#        | set board|brief_fp "<value>" | local-skills (name<TAB>path<TAB>desc lines on stdin)
#        | learn correction|preference|worked|failed|convention "<text>" [global]
#        | capture correction|preference|worked|failed|convention [global] (one lesson on stdin)
#        | forget "<text>" [global|project] | promote "<text>" [global|project] | curate | stats      (see references/learning.md)
#        | merge <old-slug> | closeout nothing_to_save|skipped
# --owner <id> anywhere on the line adds one business owner's memory: where reads it too, and note owner, learn and
# capture write to it instead of the project file. The owner comes from business/scripts/kaito-owner.mjs; no other
# owner's memory is ever read.
# The project file is keyed on the repo's network origin when it has one, else on the checkout path.
set -eu
here=$(dirname "$0")
K="${KAITO_HOME:-$HOME/.kaito}"
# Take --owner <id> out of the arguments, wherever it is.
OWN=""; ow=0; n=$#; i=0
while [ "$i" -lt "$n" ]; do
  a=$1; shift; i=$((i + 1))
  if [ "$a" = --owner ]; then
    [ "$i" -lt "$n" ] && [ "$ow" = 0 ] && [ -n "$1" ] || { echo "kaito-mem: --owner needs one owner id" >&2; exit 2; }
    OWN=$1; ow=1; shift; i=$((i + 1))
  else set -- "$@" "$a"; fi
done
OF=""; OM=""
if [ -n "$OWN" ]; then
  case "$OWN" in *[!a-z0-9-]*|-*|*-|*--*) echo "kaito-mem: owner id must be kebab-case: $OWN" >&2; exit 2 ;; esac
  # business sits beside helpmekaito in the store or the repo; a host's skills folder may link helpmekaito alone
  oc="$(cd "$here" && pwd -P)/../../business/scripts/kaito-owner.mjs"
  [ -f "$oc" ] || oc="$K/store/business/scripts/kaito-owner.mjs"
  [ -f "$oc" ] || { echo "kaito-mem: --owner needs the business skill; run ./setup in kaito-skills" >&2; exit 2; }
  orc=0; ro=$(node "$oc" resolve --owner "$OWN") || orc=$?
  [ "$orc" = 0 ] || exit "$orc"  # kaito-owner said why on stderr: 4 not found, 1 a broken record
  OM=$(printf '%s\n' "$ro" | sed -n 's/^memory=//p')
  [ -n "$OM" ] || { echo "kaito-mem: kaito-owner printed no memory folder for $OWN" >&2; exit 1; }
  ! command -v cygpath > /dev/null 2>&1 || OM=$(cygpath -u "$OM")  # Git Bash: node prints C:\..., the code below wants /c/...
  OF="$OM/owner.md"  # one file per owner: facts, rule: and learn: lines, the same format as a project file
  # a link could point at another owner's file: refuse it rather than follow it
  for x in "$OM" "$OF" "$OM/learning.log"; do
    [ ! -L "$x" ] && { [ ! -f "$x" ] || [ -z "$(find "$x" -links +1 2>/dev/null)" ]; } ||
      { echo "kaito-mem: $OWN's memory must be a real folder and files, not links: $x" >&2; exit 1; }
  done
fi
# memory.path in config moves the memory folder; default $K/memory. A missing helper means the default.
M=$(node "$here/kaito-json.mjs" get "$K/config.json" memory.path 2>/dev/null | tr -d '"') || M=""
case "$M" in "~") M=$HOME ;; "~/"*) M="$HOME/${M#"~/"}" ;; "") M="$K/memory" ;; esac
[ "${1:-}" != dir ] || { echo "$M"; exit 0; }  # kaito-obsidian.sh calls dir during a mirror: no migration, no writes
RO="memory is read-only here; to allow Codex writes run setup and answer yes to codexwrite"
. "$here/kaito-memory-lock.sh"

g=1; p=$(git rev-parse --show-toplevel 2>/dev/null) || { g=0; p=$(pwd); }
p=$(cd "$p" && pwd -P)
# ident: origin as lower-case host/path, only for a network remote. userinfo, port, query and fragment are dropped,
# so no credential is kept. An ssh host alias resolves through ssh -G. stdin is closed: capture reads the lesson from it.
ident() {
  [ "$g" = 1 ] || return 0
  u=$(git -C "$p" remote get-url origin 2>/dev/null </dev/null) || return 0
  u=${u%%[?#]*}
  case "$u" in *::*|*"["*) return 0 ;; esac  # a remote helper address, or an IPv6 host this does not parse
  case "$u" in
    *://*) sc=$(printf %s "${u%%://*}" | tr 'A-Z' 'a-z'); r=${u#*://}; h=${r%%/*}; r=${r#"$h"}; h=${h##*@}; h=${h%%:*}
      case "$sc" in ""|file|[!a-z]*|*[!a-z0-9+.-]*) return 0 ;; esac ;;
    *:*) h=${u%%:*}; r=${u#*:}; sc=ssh
      case "$h" in */*|*\\*) return 0 ;; esac
      h=${h##*@}; case "$h" in ?) return 0 ;; esac ;;  # one letter is a Windows drive
    *) return 0 ;;
  esac
  case "$sc:$h" in ssh:-*|ssh:) ;; ssh:*)
    x=$(ssh -G "$h" 2>/dev/null </dev/null | sed -n 's/^hostname //p' | head -n 1) || x=""; [ -z "$x" ] || h=$x ;; esac
  while :; do case "$r" in /*) r=${r#/} ;; *) break ;; esac; done
  r=$(printf %s "$r" | tr 'A-Z' 'a-z')
  while :; do case "$r" in */) r=${r%/} ;; *) break ;; esac; done
  r=${r%.git}
  case "$h:$r" in -*|:*|*:|*@*) return 0 ;; esac  # an @ left in the path may be part of a credential
  printf %s "$h/$r" | tr 'A-Z' 'a-z'
}
os=$(sh "$here/kaito-codegraph.sh" slug "$p")  # the checkout slug: codegraph, task caches and locks keep it
id=$(ident) || id=""
s=$os
[ -z "$id" ] || s="$(printf %s "${id##*/}" | sed 's/[^A-Za-z0-9._-]/-/g')-$(printf %s "$id" | { shasum 2>/dev/null || sha1sum; } | cut -c1-8)"
pf="$M/projects/$s.md"
of="$M/projects/$os.md"  # the file of the path key, folded into pf on the next run that can write
ix="- projects/$s.md ${id:-$p}"  # this project's MEMORY.md line
CO="$K/closeout/$s"  # "<start date> open|closed|missed" per routed task; per machine, never in the memory folder
miss=""

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
    [ -e "$pf" ] || printf "%s\n" "$ix" >> "$M/MEMORY.md"
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
  case "$1" in /*) rf=$1 ;; *) rf="$M/$1" ;; esac; shift
  [ -r "$rf" ] || exit 3
  rc=0; LC_ALL=C awk "$@" "$rf" > "$rf.$$.tmp" || rc=$?
  [ "$rc" = 0 ] && mv "$rf.$$.tmp" "$rf" && return 0
  rm -f "$rf.$$.tmp"; [ "$rc" != 4 ] || exit 4; exit 3
}
# wfail <status of a write subshell>: 3 is a failed rewrite, 74 a busy lock, anything else is memory we may not write.
wfail() {
  case "$1" in 74) echo "kaito-mem: memory is busy; nothing was saved" >&2; exit 74 ;; 3) echo "kaito-mem: could not rewrite the memory file; nothing was changed" >&2; exit 1 ;; *) echo "$RO"; exit 0 ;; esac
}
# target: where learn and capture write. f stays the memory-relative name for mirror; fp is the file, LD the folder
# locked, MK the folder made, ls the name learning.log counts it under. With --owner it is the owner's file only.
target() {
  if [ -n "$OWN" ]; then f=$OF; fp=$OF; LD=$OM; MK=$OM; LL="$OM/learning.log"; ls="owner:$OWN"
  else fp="$M/$f"; LD=$M; MK="$M/projects"; LL="$M/learning.log"; ls=$s; fi
}
# relearn forget|promote "<text>" [global|project]: drop the matching learning, or turn it into a "rule:" line.
# With --owner, only the owner file is changed. Otherwise search project, then global.
relearn() {
  case "${3:-}:$OWN" in :*|global:|project:|owner:?*) ;; *) set -- "$1" "" ;; esac
  [ -z "$OWN" ] || set -- "$1" "$2" owner
  [ -n "$2" ] || { echo "usage: kaito-mem.sh $1 \"<text>\" [global|project] | $1 \"<text>\" [owner] --owner <id>" >&2; exit 2; }
  for f in ${OF:+"$OF"} "projects/$s.md" "${po:+projects/$os.md}" global.md; do
    case "${3:-}:$f" in project:global.md|project:/*|global:projects/*|global:/*|owner:global.md|owner:projects/*) continue ;; esac
    case "$f" in /*) ff=$f; fl=$OM ;; *) ff="$M/$f"; fl=$M ;; esac
    [ -f "$ff" ] || continue
    rc=0
    (
      memory_lock "$fl" || exit $?
      T=$2; export T
      rewrite "$f" -v mode="$1" "$AWKLIB"'
        BEGIN { n = norm(ENVIRON["T"]) }
        !hit && /^learn:/ && norm(txt($0)) == n { hit = 1; if (mode == "promote") print "rule: " txt($0); next }
        { print }
        END { exit hit ? 0 : 4 }'
    ) 2>/dev/null || rc=$?
    case "$rc:$f" in 0:/*) return 0 ;; 0:*) mirror "$f"; return 0 ;; 4:*) ;; *) wfail "$rc" ;; esac
  done
  echo "kaito-mem: no such learning; copy its text from kaito-mem.sh curate" >&2; exit 1
}
# Each file ends its own last line, and a CR from a Windows editor is dropped.
learnings() {
  for lf in "$pf" "$po" ${OF:+"$OF"} "$M/global.md"; do [ ! -r "$lf" ] || awk 1 "$lf"; done 2>/dev/null | tr -d '\r' | grep '^learn:' || :
}
# The project file, and an old one still waiting to be folded in.
pfs() { for x in "$pf" "$po"; do [ ! -r "$x" ] || awk 1 "$x"; done; }
# fold <old-slug>: merge projects/<old-slug>.md into this project's file, re-key the index and the log, retire it last.
# Call inside a locked subshell; every step checks its own status (errexit is off there). A rerun after a crash
# converges: the merge keeps the higher count, never a sum, and skips lines already present.
fold() {
  ol=$1; o="$M/projects/$ol.md"
  [ -f "$o" ] || exit 0
  if [ -f "$pf" ]; then set -- f=n "$pf" f=o "$o"; else set -- f=o "$o"; fi
  LC_ALL=C awk "$AWKLIB"'
    { sub("\r$", "") }
    f == "n" { o[++n] = $0
      if (/^learn:/) { k = norm(txt($0)); if (!(k in L)) { L[k] = n; kd[n] = $2; c[n] = $3 + 0; d[n] = $4 } }
      else if (/^brief_fp:/) bf = 1
      else if (/^codegraph:/) cg = 1
      else if (/^local_skill:/) nl[n] = 1
      else seen[$0] = 1
      next }
    /^(tracker|board|tracking):/ { next }
    /^learn:/ { k = norm(txt($0))
      if (k in L) { i = L[k]; if ($3 + 0 > c[i]) { c[i] = $3 + 0; up[i] = 1 }; if ($4 > d[i]) { d[i] = $4; up[i] = 1 } }
      else { o[++n] = $0; L[k] = n; kd[n] = $2; c[n] = $3 + 0; d[n] = $4 }
      next }
    /^(brief_fp|local_skill):/ { o[++n] = $0; ol[n] = 1; if (/^brief_fp:/) obf = 1; next }
    /^codegraph:/ { if (!cg) { o[++n] = $0; cg = 1 }; next }
    $0 != "" && !($0 in seen) { o[++n] = $0; seen[$0] = 1 }
    END { theirs = !bf && obf  # brief_fp and local_skill lines come from one file
      for (i = 1; i <= n; i++) {
        if (theirs && (i in nl)) continue
        if (!theirs && (i in ol)) continue
        if (i in up) print "learn: " kd[i] " " c[i] " " d[i] " " txt(o[i]); else print o[i] } }' "$@" > "$pf.$$.tmp" 2>/dev/null &&
    mv "$pf.$$.tmp" "$pf" 2>/dev/null || { rm -f "$pf.$$.tmp" 2>/dev/null; exit 1; }
  KAITO_TODAY=$today node "$here/kaito-trackers.mjs" "$pf" merge "$o" >/dev/null || exit 1
  { [ -e "$M/MEMORY.md" ] || : > "$M/MEMORY.md"; } 2>/dev/null || exit 1
  MA="- projects/$ol.md" MB="- projects/$s.md" MI=$ix; export MA MB MI
  rewrite MEMORY.md '
    { x = $0; sub("\r$", "", x) }
    x == ENVIRON["MA"] || index(x, ENVIRON["MA"] " ") == 1 { next }
    x == ENVIRON["MB"] || index(x, ENVIRON["MB"] " ") == 1 { if (!hit) print ENVIRON["MI"]; hit = 1; next }
    { print }
    END { if (!hit) print ENVIRON["MI"] }' 2>/dev/null
  if [ -f "$M/learning.log" ]; then
    MO=$ol MN=$s; export MO MN
    rewrite learning.log '
      { x = $0; sub("\r$", "", x); q = x; sub(/^[^ ]+ /, "", q); sub(/ [^ ]+$/, "", q) }
      NF >= 3 && q == ENVIRON["MO"] { k = split(x, a, " "); print a[1] " " ENVIRON["MN"] " " a[k]; next }
      { print }' 2>/dev/null
  fi
  mkdir -p "$M/projects/.migrated" 2>/dev/null || exit 1
  b="$M/projects/.migrated/$ol.md"; i=0
  while [ -e "$b" ]; do i=$((i + 1)); b="$M/projects/.migrated/$ol.md.$i"; done
  mv "$o" "$b" 2>/dev/null || exit 1
}
# migrate: fold the path-keyed file in when it is pending. Silent; when it cannot run, reads include the old file.
migrate() {
  [ "$s" != "$os" ] && [ -f "$of" ] || return 0
  ( memory_lock "$M" || exit $?; fold "$os" ) || return 0  # stderr kept for a tracker conflict warning
  mirror "projects/$s.md" MEMORY.md
}
# co start|close: update this project's closeout state. Best effort: silent, never changes the command's result.
co() {
  [ ! -e "$CO" ] || [ -r "$CO" ] || return 0
  last=$(tail -n 1 "$CO" 2>/dev/null | tr -d '\r') || last=""
  case "$1:$last" in close:*" open"|start:*) ;; *) return 0 ;; esac
  ( mkdir -p "$K/closeout" && { cat "$CO" 2>/dev/null || :; } | LC_ALL=C awk -v m="$1" -v today="$today" "$AWKLIB"'
      { sub("\r$", "") } $0 != "" { l[++n] = $0 }
      END { w = m == "start" ? " missed" : " closed"; if (n) sub(/ open$/, w, l[n]); if (m == "start") l[++n] = today " open"
        for (i = 1; i <= n; i++) { split(l[i], a, " ")
          if (m != "start" || (a[1] ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ && days(today) - days(a[1]) <= 28)) print l[i] } }' > "$CO.$$.tmp" &&
    mv "$CO.$$.tmp" "$CO" ) 2>/dev/null || { rm -f "$CO.$$.tmp" 2>/dev/null; return 0; }
  case "$1:$last" in start:*" open") miss=${last%% *} ;; esac
}

case "${1:-}" in closeout) ;; *) migrate ;; esac
po=""; [ "$s" = "$os" ] || [ ! -f "$of" ] || po=$of  # still pending: reads include it, writes go to pf

case "${1:-}" in
  slug) echo "$s" ;;
  label) echo "${id:-$p}" ;;
  where)
    [ $# -ne 2 ] || [ "$2" != task ] || co start  # a routed task starts: an earlier one still open had no closeout
    if [ "$g" = 0 ] || [ "$p" = / ] || [ "$p" = "$(cd "$HOME" && pwd -P)" ]; then i=n/a
    elif [ -e "$p/.codegraph" ]; then i=yes; else i=no; fi  # a dangling link is not an index
    # top is never cut: keyed lines, rules, then the most confirmed, most recent learnings of this project and user
    L=$(learnings | sort -k3,3nr -k4,4r); n=$(printf "%s\n" "$L" | grep -c . || :)
    top=$(printf "%s\n" "slug=$s" "project_file=$pf" "indexed=$i"
      [ -z "$OWN" ] || printf "%s\n" "owner=$OWN" "owner_file=$OF"
      [ -z "$miss" ] || echo "closeout_missed: a task started $miss has no recorded closeout and may still be running"
      { pfs | grep -E '^(tracker|tracking|board|local_skill|rule):' || :
        [ -z "$OF" ] || grep '^rule:' "$OF" || :; grep '^rule:' "$M/global.md" || :
        [ "$n" -eq 0 ] || printf "%s\n" "$L" | head -n "$LEARN_CAP"
        [ "$n" -le "$LEARN_CAP" ] || echo "learn_more: $((n - LEARN_CAP)) not shown; run kaito-mem.sh curate${OWN:+ --owner $OWN}"; } 2>/dev/null)
    rest=$({ [ -z "$OF" ] || grep -vE '^(rule|learn):' "$OF" || :  # the owner's facts first: business work is about them
      pfs | grep -vE '^(tracker|tracking|board|local_skill|rule|learn):' || :
      grep -vE '^(rule|learn):' "$M/global.md" || :; cat "$M/MEMORY.md" || :; } 2>/dev/null)  # project facts first: they survive the cut
    printf "%s\n" "$top"
    room=$((40 - $(printf "%s\n" "$top" | wc -l))); nr=0; [ -z "$rest" ] || nr=$(printf "%s\n" "$rest" | wc -l)
    if [ "$nr" -le "$room" ]; then [ "$nr" -eq 0 ] || printf "%s\n" "$rest"
    else [ "$room" -le 1 ] || printf "%s\n" "$rest" | head -n $((room - 1)); echo ...; fi
    ;;
  note)
    [ $# -eq 3 ] || { echo "usage: kaito-mem.sh note global|project \"<text>\" | note owner \"<text>\" --owner <id>" >&2; exit 2; }
    nosecret "$3"; nokey "$3"
    t=$(printf %s "$3" | tr '\n\r' '  ')  # one note, one line: no injected lines
    # with --owner only the owner's file: a global or project note would be read in every other owner's tasks
    case "$2:$OWN" in global:|project:) ;; owner:?*) ;; *) echo "kaito-mem: use note global|project without --owner, or note owner with --owner <id>" >&2; exit 2 ;; esac
    case "$2" in global) f=global.md ;; project) f=projects/$s.md ;; owner) f="" ;; esac
    if [ -z "$f" ]; then
      ( mkdir -p "$OM" || exit 73; memory_lock "$OM" || exit $?; printf "%s\n" "- $(date +%Y-%m-%d) $t" >> "$OF" ) 2>/dev/null || wfail $?
      exit 0
    fi
    (
      mkdir -p "$M/projects" || exit 1
      memory_lock "$M" || exit $?
      if [ "$2" = project ] && [ ! -e "$pf" ]; then
        printf "%s\n" "$ix" >> "$M/MEMORY.md"
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
    [ -z "$OWN" ] || [ "${4:-project}" = project ] || ok=0  # an owner lesson is the owner's, never global
    [ "$ok" = 1 ] && [ -n "$(printf %s "$t" | tr -d ' ')" ] ||
      { echo "usage: kaito-mem.sh learn correction|preference|worked|failed|convention \"<text>\" [global] | learn <kind> \"<text>\" --owner <id>" >&2; exit 2; }
    nosecret "$t"; nokey "$t"
    target
    (
      mkdir -p "$MK" || exit 1
      memory_lock "$LD" || exit $?
      new=0; [ "$f" = global.md ] || [ -n "$OWN" ] || [ -e "$pf" ] || new=1
      [ -e "$fp" ] || : > "$fp" || exit 3
      T=$t; export T
      # the same text again, whatever the kind, confirms the learning: count up, date to today
      rewrite "$f" -v k="$2" -v d="$today" "$AWKLIB"'
        BEGIN { t = ENVIRON["T"]; n = norm(t) }
        !hit && /^learn:/ && norm(txt($0)) == n { hit = 1; print "learn: " $2 " " $3 + 1 " " d " " txt($0); next }
        { print }
        END { if (!hit) print "learn: " k " 1 " d " " t }'
      # only a learning that is on disk is indexed and logged
      [ "$new" = 0 ] || printf "%s\n" "$ix" >> "$M/MEMORY.md" || :
      printf "%s\n" "$today $ls $2" >> "$LL" || :  # one line per capture: what stats counts
    ) 2>/dev/null || wfail $?
    [ -n "$OWN" ] || mirror "$f" MEMORY.md
    ;;
  capture)
    ok=1; t=$(tr '\n\r' '  ' | sed 's/[[:space:]]*$//')
    case "${2:-}" in correction|preference|worked|failed|convention) ;; *) ok=0 ;; esac
    case "${3:-project}" in project) f=projects/$s.md ;; global) f=global.md ;; *) ok=0 ;; esac
    case "${3:-project}:${2:-}" in global:correction|global:preference|project:*) ;; *) ok=0 ;; esac
    [ -z "$OWN" ] || [ "${3:-project}" = project ] || ok=0  # an owner lesson is the owner's, never global
    [ "$ok" = 1 ] && [ -n "$(printf %s "$t" | tr -d ' ')" ] ||
      { echo "usage: kaito-mem.sh capture correction|preference|worked|failed|convention [global] < lesson | capture <kind> --owner <id> < lesson" >&2; exit 2; }
    nosecret "$t"; nokey "$t"
    target
    rc=0
    (
      mkdir -p "$MK" || exit 73
      memory_lock "$LD" || exit $?
      new=0; [ "$f" = global.md ] || [ -n "$OWN" ] || [ -e "$pf" ] || new=1
      T=$t; export T
      w=0
      if [ -e "$fp" ]; then
        rewrite "$f" -v k="$2" -v d="$today" "$AWKLIB"' \
          BEGIN { t = ENVIRON["T"]; n = norm(t) }
          /^learn:/ && norm(txt($0)) == n { hit = 1 }
          { print }
          END { if (!hit) print "learn: " k " 1 " d " " t; exit hit ? 4 : 0 }' || w=$?
      else
        printf '%s\n' "learn: $2 1 $today $t" > "$fp.$$.tmp" || exit 1
        mv "$fp.$$.tmp" "$fp" || { rm -f "$fp.$$.tmp"; exit 1; }
      fi
      [ "$w" = 4 ] && exit 4
      [ "$w" = 0 ] || exit 1
      LC_ALL=C awk "$AWKLIB"'
        BEGIN { n = norm(ENVIRON["T"]) }
        /^learn:/ && norm(txt($0)) == n { found = 1 }
        END { exit found ? 0 : 1 }' "$fp" || exit 1
      [ "$new" = 0 ] || printf "%s\n" "$ix" >> "$M/MEMORY.md" || echo "kaito-mem: warning: the project index was not updated" >&2
      printf "%s\n" "$today $ls $2" >> "$LL" || echo "kaito-mem: warning: the learning log was not updated" >&2
    ) || rc=$?
    co close  # the lesson was assessed, saved or not
    case "$rc" in
      0) [ -n "$OWN" ] || mirror "$f" MEMORY.md; echo saved ;;
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
    { cat "$CO" 2>/dev/null || :; } | LC_ALL=C awk -v today="$today" "$AWKLIB"'
      { sub("\r$", ""); a = days(today) - days($1) }
      $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ && a >= 0 && a < 28 { if ($NF == "missed") n++; if ($NF == "missed" || $NF == "closed") m++ }
      END { print "closeouts not recorded: " n + 0 " of " m + 0 " routed tasks started in the last 28 days" }'
    ;;
  closeout)
    case "$#:${2:-}" in 2:nothing_to_save|2:skipped) ;; *) echo "usage: kaito-mem.sh closeout nothing_to_save|skipped" >&2; exit 2 ;; esac
    co close; echo "$2"
    ;;
  merge)
    case "${2:-}" in ""|*/*|*..*) echo "usage: kaito-mem.sh merge <old-slug> (a projects/ file name without .md)" >&2; exit 2 ;; esac
    [ "$2" != "$s" ] && [ ! "$M/projects/$2.md" -ef "$pf" ] || { echo "kaito-mem: $2 is this project's own file" >&2; exit 2; }
    [ "$2" != "$os" ] || [ -f "$of" ] || { echo "merged: $2 -> $s"; exit 0; }  # the run above already folded it in
    [ -f "$M/projects/$2.md" ] || { echo "kaito-mem: no such project file: projects/$2.md" >&2; exit 2; }
    rc=0; ( memory_lock "$M" || exit $?; fold "$2" ) || rc=$?
    case "$rc" in
      0) mirror "projects/$s.md" MEMORY.md; echo "merged: $2 -> $s" ;;
      73) echo "$RO" >&2; exit 73 ;;
      74) echo "kaito-mem: memory is busy; nothing was merged" >&2; exit 74 ;;
      *) echo "kaito-mem: the merge did not finish; projects/$2.md was kept, run it again" >&2; exit 1 ;;
    esac
    ;;
  *) echo "usage: kaito-mem.sh dir | slug | label | where [task] | note global|project|owner \"<text>\" | codegraph-decision yes|no | set board|brief_fp \"<value>\" | local-skills | learn <kind> \"<text>\" [global] | capture <kind> [global] < lesson | forget|promote \"<text>\" [global|project|owner] | curate | stats | merge <old-slug> | closeout nothing_to_save|skipped; add --owner <id> for one business owner's memory" >&2; exit 2 ;;
esac
