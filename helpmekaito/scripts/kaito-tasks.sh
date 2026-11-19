#!/bin/sh
# Tasks for the current project. Trello: the board is the truth, tasks/trello/<slug>/ is a read cache.
# Obsidian: one note per task under tasks/<slug>/, no remote. Other managers go through their MCP.
# Usage: kaito-tasks.sh status | login | boards | consent yes|no <boardId>... | discover | map <boardId> | pull | list
#   add "<title>" [--list <name|id>] [--due <iso>] [--desc <text>] | item add <task> "<text>"
#   check|uncheck <task> <item> | rename <task> "<title>" | move <task> <list|status>
#   comment <task> "<text>" | done <task> | reopen <task>
set +x  # never trace: credentials are read below
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
K="${KAITO_HOME:-$HOME/.kaito}"
CFG="$K/config.json"
USAGE="usage: kaito-tasks.sh status|login|boards|consent|discover|map|pull|list|add|item add|check|uncheck|rename|move|comment|done|reopen"
cfg() { node "$here/kaito-json.mjs" get "$CFG" "$1" 2>/dev/null | sed 's/^"\(.*\)"$/\1/'; }
die() { echo "kaito-tasks: $*" >&2; exit 1; }

mgr=$(cfg tasks.manager)
cmd=${1:-}
M=$(sh "$here/kaito-mem.sh" dir)
p=$(git rev-parse --show-toplevel 2>/dev/null) || p=$(pwd)
p=$(cd "$p" && pwd -P)
S=$(sh "$here/kaito-codegraph.sh" slug "$p")
pf="$M/projects/$S.md"
# The project's own board line picks the manager; tasks.manager in config is the default.
bm=$(sed -n 's/^board: \([a-z]*\) .*/\1/p' "$pf" 2>/dev/null | head -n1)
case "$bm" in trello|obsidian) mgr=$bm ;; esac
case "$mgr" in
  trello|obsidian) ;;
  "") [ "$cmd" = status ] || die "no task manager set: run setup"
      echo "manager: none"; echo "onboarding: $(cfg tasks.state || :)"; exit 0 ;;
  *) echo "use the $mgr MCP; see references/tasks.md"; exit 0 ;;
esac

# Trello cache and Obsidian notes never share a folder, so a pull cannot delete notes.
if [ "$mgr" = trello ]; then D="$M/tasks/trello/$S"; else D="$M/tasks/$S"; fi
board=$(grep '^board: ' "$pf" 2>/dev/null | head -n1) || board=""
B=$(printf %s "$board" | awk '{print $3}')
export M S D B MGR="$mgr"

# Credentials: env pair, else ~/.kaito/.env, else ~/.config/trello/.env. Key and token from one source, read as data.
envval() { sed -n "s/^\(export \)\{0,1\}$1=//p" "$2" 2>/dev/null | head -n1 | tr -d '\r' | sed "s/^\"\(.*\)\"\$/\1/; s/^'\(.*\)'\$/\1/"; }
creds() {
  if [ -n "${TRELLO_KEY:-}" ] && [ -n "${TRELLO_TOKEN:-}" ]; then
    KAITO_TRELLO_KEY=$TRELLO_KEY; KAITO_TRELLO_TOKEN=$TRELLO_TOKEN; SRC=env; return 0
  fi
  for f in "$K/.env" "$HOME/.config/trello/.env"; do
    KAITO_TRELLO_KEY=$(envval TRELLO_KEY "$f"); KAITO_TRELLO_TOKEN=$(envval TRELLO_TOKEN "$f")
    if [ -n "$KAITO_TRELLO_KEY" ] && [ -n "$KAITO_TRELLO_TOKEN" ]; then SRC=$f; return 0; fi
  done
  KAITO_TRELLO_KEY=""; KAITO_TRELLO_TOKEN=""; return 1
}
need_creds() {
  creds || die "no Trello credentials: run 'sh $here/kaito-tasks.sh login' in a terminal"
  export KAITO_TRELLO_KEY KAITO_TRELLO_TOKEN  # node gets them from env, never argv
}
need_board() { [ -n "$B" ] || die "no board mapped for this project: run kaito-tasks.sh boards, then map <boardId>"; }

# One memory writer at a time, same lock as kaito-mem.sh. ponytail: a lock left by a killed run is taken over after 2s.
mlock() {
  [ -w "$M" ] || return 1
  i=0; until mkdir "$M/.lock" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -eq 20 ]; then rmdir "$M/.lock" 2>/dev/null || :; fi
    [ "$i" -le 21 ] || return 1
    sleep 0.1
  done
  trap 'rmdir "$M/.lock" 2>/dev/null || :' EXIT
}

# The node side lives in kaito-tasks.mjs and providers/<manager>.mjs.
J() { node "$here/kaito-tasks.mjs" "$@"; }

case "$cmd" in
  status)
    echo "manager: $mgr"
    if [ "$mgr" = trello ]; then
      if creds; then echo "credentials: yes ($SRC)"; else echo "credentials: no"; fi
      echo "${board:-board: none}"
    else echo "notes: $D"; fi
    c=$(cfg tasks.discovery.consent)
    if [ -n "$c" ]; then echo "discovery: $c $(cfg tasks.discovery.at) ($(node "$here/kaito-json.mjs" each "$CFG" tasks.discovery.boards | tr '\n' ' ' | sed 's/ $//'))"
    else echo "discovery: not asked"; fi
    s=$(cfg tasks.state); echo "onboarding: ${s:-pending}"
    ;;
  login)
    [ "$mgr" = trello ] || die "login is for Trello; the manager is $mgr"
    [ -t 0 ] && [ -t 1 ] || die "login reads secrets, so run it in a terminal: sh $here/kaito-tasks.sh login"
    cat <<EOF
Trello needs an API key and a token.
  1. Open https://trello.com/power-ups/admin and make a new Power-Up (any name, any workspace).
  2. Open it, go to API key, and generate a new API key. Copy the key.
  3. On that page, follow the link to generate a token (the authorize link next to the key). Allow, then copy the token.
They are saved to $K/.env (mode 600). Nothing is echoed.
The Trello MCP is optional and separate: add it from your agent's MCP or connector settings (see references/tasks.md).

EOF
    old=$(stty -g)
    trap 'stty "$old" 2>/dev/null || :' EXIT
    trap 'stty "$old" 2>/dev/null || :; exit 130' INT TERM
    stty -echo
    printf "Trello API key: "; IFS= read -r key || key=""; echo
    printf "Trello token: "; IFS= read -r tok || tok=""; echo
    stty "$old"
    case "$key$tok" in *[!A-Za-z0-9]*) die "that does not look like a Trello key and token; nothing saved" ;; esac
    [ -n "$key" ] && [ -n "$tok" ] || die "key and token are both needed; nothing saved"
    u=$(KAITO_TRELLO_KEY=$key KAITO_TRELLO_TOKEN=$tok J me 2>/dev/null) || die "Trello did not accept that key and token; nothing saved"
    (
      umask 077; mkdir -p "$K"; t="$K/.env.$$.tmp"
      { grep -v -e '^TRELLO_KEY=' -e '^TRELLO_TOKEN=' -e '^export TRELLO_KEY=' -e '^export TRELLO_TOKEN=' "$K/.env" 2>/dev/null || :
        printf 'TRELLO_KEY=%s\nTRELLO_TOKEN=%s\n' "$key" "$tok"; } > "$t"
      chmod 600 "$t"; mv "$t" "$K/.env"
    )
    node "$here/kaito-json.mjs" set "$CFG" tasks.steps.credentials true
    echo "saved Trello credentials for $u to $K/.env"
    ;;
  boards) need_creds; J boards ;;
  consent)
    case "${2:-}" in yes|no) ;; *) die "usage: kaito-tasks.sh consent yes|no <boardId>..." ;; esac
    a=$2; shift 2
    [ "$a" = no ] || [ $# -gt 0 ] || die "consent yes needs the board ids to discover"
    list=""; for b in "$@"; do
      case "$b" in ""|*[!A-Za-z0-9]*) die "bad board id $b" ;; esac
      list="$list${list:+,}\"$b\""
    done
    node "$here/kaito-json.mjs" set "$CFG" tasks.discovery "{\"consent\":\"$a\",\"boards\":[$list],\"at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
    [ "$a" = yes ] || node "$here/kaito-json.mjs" set "$CFG" tasks.steps.discovery true  # yes: done once discover succeeds
    echo "discovery consent: $a${list:+ for $*}"
    ;;
  discover)
    [ "$mgr" = trello ] || die "discover is for Trello"
    [ "$(cfg tasks.discovery.consent)" = yes ] || die "no discovery consent: ask first, then run kaito-tasks.sh consent yes <boardId>..."
    bs=$(node "$here/kaito-json.mjs" each "$CFG" tasks.discovery.boards)
    [ -n "$bs" ] || die "consent lists no boards"
    need_creds
    # shellcheck disable=SC2086  # ids are checked to [A-Za-z0-9] by consent
    J discover $bs
    node "$here/kaito-json.mjs" set "$CFG" tasks.steps.discovery true
    ;;
  map)
    [ "$mgr" = trello ] || die "map is for Trello"
    id=${2:-}; case "$id" in ""|*[!A-Za-z0-9]*) die "usage: kaito-tasks.sh map <boardId>" ;; esac
    need_creds
    name=$(J board-name "$id")  # fetched before the lock: never hold it across a network call
    (
      mkdir -p "$M/projects"; mlock
      [ -e "$pf" ] || printf "%s\n" "- projects/$S.md $p" >> "$M/MEMORY.md"
      { grep -v '^board:' "$pf" 2>/dev/null || :; echo "board: trello $id $name"; } > "$pf.$$.tmp"
      mv "$pf.$$.tmp" "$pf"
    ) || die "could not write $pf"
    if [ -x "$here/kaito-obsidian.sh" ]; then "$here/kaito-obsidian.sh" push "projects/$S.md" >/dev/null 2>&1 || :; fi
    echo "board: trello $id $name"
    ;;
  pull)
    if [ "$mgr" = obsidian ]; then echo "obsidian notes are the source; nothing to pull"; exit 0; fi
    need_board; need_creds; J pull ;;
  list) J list ;;
  add|check|uncheck|rename|move|comment|done|reopen|item)
    op=$cmd; shift
    if [ "$op" = item ]; then [ "${1:-}" = add ] || die "usage: kaito-tasks.sh item add <task> \"<text>\""; op=item-add; shift; fi
    if [ "$mgr" = trello ]; then need_board; need_creds; fi
    J op "$op" "$@"
    ;;
  *) echo "$USAGE" >&2; exit 2 ;;
esac
