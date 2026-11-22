#!/bin/sh
# Tasks for the current project. Trello, Plane and Linear: the board (Plane: project or module; Linear: team or project) is the truth,
# tasks/<manager>/<slug>/ is a read cache. Obsidian: one note per task under tasks/<slug>/, no remote.
# Other managers go through their MCP.
# A project can have several trackers (lines in its memory file); --tracker <manager> picks one, else the first scripted one.
# Usage: kaito-tasks.sh [--tracker <manager>] <command>
#   detect | tracker list|add <manager> <id> [name] [key=value...]|set <manager> key=value...|rm <manager> | tracking never|ask
#   status | login | boards | modules <projectId> | projects <teamId> | consent yes|no <boardId>... | discover
#   map <boardId> (Plane: <projectId>[/<moduleId>], Linear: <teamId>[/<projectId>]) | pull | list
#   structure put plane|linear (JSON on stdin)
#   add "<title>" [--list <name|id>] [--due <iso>] [--desc <text>] | item add <task> "<text>"
#   check|uncheck <task> <item> | rename <task> "<title>" | move <task> <list|status>
#   comment <task> "<text>" | link <task> <url> ["<title>"] | done <task> | reopen <task>
set +x  # never trace: credentials are read below
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
K="${KAITO_HOME:-$HOME/.kaito}"
CFG="$K/config.json"
USAGE="usage: kaito-tasks.sh [--tracker <manager>] detect|tracker|tracking|status|login|boards|modules|projects|consent|discover|map|pull|list|structure put|add|item add|check|uncheck|rename|move|comment|link|done|reopen"
cfg() { node "$here/kaito-json.mjs" get "$CFG" "$1" 2>/dev/null | sed 's/^"\(.*\)"$/\1/'; }
die() { echo "kaito-tasks: $*" >&2; exit 1; }

want=""
if [ "${1:-}" = --tracker ]; then
  want=${2:-}; case "$want" in ""|*[!a-z0-9-]*) die "usage: kaito-tasks.sh --tracker <manager> <command>" ;; esac
  shift 2
fi
mgr=$(cfg tasks.manager)
cmd=${1:-}
M=$(sh "$here/kaito-mem.sh" dir)
p=$(git rev-parse --show-toplevel 2>/dev/null) || p=$(pwd)
p=$(cd "$p" && pwd -P)
S=$(sh "$here/kaito-codegraph.sh" slug "$p")
MS=$(sh "$here/kaito-mem.sh" slug)  # the memory key (repo identity); S stays the checkout slug for cache, lock and temp names
pf="$M/projects/$MS.md"
[ -e "$pf" ] || [ ! -e "$M/projects/$S.md" ] || pf="$M/projects/$S.md"  # the old file is still waiting to be folded in: use it
TK="$here/kaito-trackers.mjs"

. "$here/kaito-memory-lock.sh"

mlock() {
  rc=0
  memory_lock "$M" || rc=$?
  case "$rc" in
    0) return 0 ;;
    73) die "memory is read-only here" ;;
    74) die "memory is busy; try again after the other write finishes" ;;
    *) die "could not lock memory" ;;
  esac
}
# index_line: a new project file gets its MEMORY.md line; kaito-mem.sh owns the text after the file name.
index_line() { [ -e "$pf" ] || printf "%s\n" "- projects/$MS.md $(sh "$here/kaito-mem.sh" label)" >> "$M/MEMORY.md"; }
# tk_write <kaito-trackers args>: change the project's tracker lines under the lock, then mirror the file.
tk_write() {
  out=$(
    mkdir -p "$M/projects" || die "could not open memory"
    mlock
    index_line
    node "$TK" "$pf" "$@"
  ) || exit 1
  if [ -x "$here/kaito-obsidian.sh" ]; then "$here/kaito-obsidian.sh" push "projects/$MS.md" >/dev/null 2>&1 || :; fi
  printf "%s\n" "$out"
}

# These work before any manager is chosen: they are how a project gets its trackers.
case "$cmd" in
  detect) node "$here/kaito-detect.mjs" "$p" "$M"; exit 0 ;;
  tracker)
    case "${2:-}" in
      list) node "$TK" "$pf" list ;;
      add) [ $# -ge 4 ] || die "usage: kaito-tasks.sh tracker add <manager> <id> [name] [role=official|personal] [tracking=always|never|ask] [note=<text>]"
           shift 2; m=$1; id=$2; shift 2
           case "${1:-}" in ""|role=*|tracking=*|note=*) name="" ;; *) name=$1; shift ;; esac
           tk_write add "$m" "$id" "$name" "$@" ;;
      set|rm) [ $# -ge 3 ] || die "usage: kaito-tasks.sh tracker ${2} <manager> ..."; sub=$2; shift 2; tk_write "$sub" "$@" ;;
      *) die "usage: kaito-tasks.sh tracker list|add|set|rm" ;;
    esac
    exit 0 ;;
  tracking) tk_write project "${2:-}"; exit 0 ;;
esac

# The project's tracker lines pick the manager; tasks.manager in config is only the default.
# KAITO_TASKS_MANAGER is for setup: it onboards one manager for the machine, whatever tracker the folder it runs in has.
# --tracker <manager> on a project without that tracker yet does the same for the commands that set one up,
# so a second tracker can be added on a machine whose default manager is another one.
setup_cmd() { case "$cmd" in status|login|boards|modules|projects|consent|discover|map) return 0 ;; esac; return 1; }
forced=""; boot=""
if [ -z "$want" ]; then case "${KAITO_TASKS_MANAGER:-}" in trello|plane|linear|obsidian) forced=$KAITO_TASKS_MANAGER; want=$forced ;; esac
else case "$want" in trello|plane|linear)
  if setup_cmd && ! node "$TK" "$pf" select "$want" >/dev/null 2>&1; then forced=$want; boot=1; fi ;; esac
fi
sel=$(node "$TK" "$pf" select "$want" 2>/dev/null) || { [ -n "$forced" ] || { node "$TK" "$pf" select "$want" >/dev/null; exit 1; }; sel=""; }
tm=$(printf '%s\n' "$sel" | sed -n 1p); B=$(printf '%s\n' "$sel" | sed -n 2p)
TRK=$(printf '%s\n' "$sel" | sed -n 3p); scripted=$(printf '%s\n' "$sel" | sed -n 4p)
# A tracker only its MCP can drive (a Linear line keyed by team key) goes to the MCP, unless it is being set up again.
if [ "$(printf '%s\n' "$sel" | sed -n 5p)" = mcp ] && [ -z "$forced" ]; then
  setup_cmd || { echo "use the $tm MCP; see references/tasks.md"; exit 0; }
  forced=$tm; boot=1
fi
[ -z "$tm" ] || mgr=$tm
if [ -n "$forced" ]; then
  mgr=$forced; TRK=""; want=""
  # A project set to tracking: never stays off while a new tracker is set up: discover and map refuse.
  if [ -n "$boot" ] && grep -q -E '^(tracking: never|board: none)[[:space:]]*$' "$pf" 2>/dev/null; then TRK=never; PNEVER=1; fi
fi
case "$mgr" in
  trello|plane|linear|obsidian) ;;
  ""|none) [ "$cmd" = status ] || die "no task manager set: run setup"
      echo "manager: none"; echo "onboarding: $(cfg tasks.state || :)"; exit 0 ;;
  *) echo "use the $mgr MCP; see references/tasks.md"; exit 0 ;;
esac
[ "$B" != - ] || B=""

# A remote cache and Obsidian notes never share a folder, so a pull cannot delete notes.
case "$mgr" in trello|plane|linear) D="$M/tasks/$mgr/$S" ;; *) D="$M/tasks/$S" ;; esac
board=$(grep "^board: $mgr " "$pf" 2>/dev/null | head -n1) || board=""
# Tracking off (for this tracker, or for the whole project) means no reads and no writes.
off() {
  [ "$TRK" = never ] || return 1
  if [ -n "${PNEVER:-}" ]; then echo "tracking is off for this project; turn it on with: kaito-tasks.sh tracking ask"
  else echo "tracking is off for this project${tm:+ on $tm}; turn it on with: kaito-tasks.sh tracker set <manager> tracking=always"; fi
}
# The cache folder is stamped with the tracker it was pulled for. Another checkout of the same repo may have remapped the
# project since, and Linear trusts its cache. stamp check clears a stale cache (conflicts stay); stamp write only records.
# Linear only, as drop_cache: a Plane or Trello remap keeps its cache on purpose.
stamp() {
  [ "$mgr" = linear ] && [ -n "$B" ] && [ -d "$D" ] || return 0
  was=$(cat "$D/.tracker" 2>/dev/null) || was=""
  [ "$was" != "$mgr $B" ] || return 0
  # A cache with no stamp is from before stamps: it is kept, it may hold edits not synced yet.
  if [ "$1" = check ] && [ -n "$was" ]; then find "$D" -mindepth 1 -maxdepth 1 ! -name conflicts -exec rm -rf {} + || :; fi
  printf "%s\n" "$mgr $B" > "$D/.tracker" 2>/dev/null || :  # best effort: never fails a command that already ran
}
export M S D B MGR="$mgr"
# Discovery consent is kept per manager, so answering for one never drops the other's boards. Trello keeps the first key.
DK=tasks.discovery; [ "$mgr" = trello ] || DK="tasks.discovery_$mgr"

# Credentials: env, else ~/.kaito/.env (Trello also ~/.config/trello/.env, Linear ~/.config/linear/.env). All values of one manager from one source, read as data.
envval() { sed -n "s/^\(export \)\{0,1\}$1=//p" "$2" 2>/dev/null | head -n1 | tr -d '\r' | sed "s/^\"\(.*\)\"\$/\1/; s/^'\(.*\)'\$/\1/"; }
creds_trello() {
  if [ -n "${TRELLO_KEY:-}" ] && [ -n "${TRELLO_TOKEN:-}" ]; then
    KAITO_TRELLO_KEY=$TRELLO_KEY; KAITO_TRELLO_TOKEN=$TRELLO_TOKEN; SRC=env; return 0
  fi
  for f in "$K/.env" "$HOME/.config/trello/.env"; do
    KAITO_TRELLO_KEY=$(envval TRELLO_KEY "$f"); KAITO_TRELLO_TOKEN=$(envval TRELLO_TOKEN "$f")
    if [ -n "$KAITO_TRELLO_KEY" ] && [ -n "$KAITO_TRELLO_TOKEN" ]; then SRC=$f; return 0; fi
  done
  KAITO_TRELLO_KEY=""; KAITO_TRELLO_TOKEN=""; return 1
}
# Plane: PLANE_API_KEY and PLANE_WORKSPACE (the workspace slug); PLANE_BASE_URL only for a self-hosted Plane.
creds_plane() {
  if [ -n "${PLANE_API_KEY:-}" ] && [ -n "${PLANE_WORKSPACE:-}" ]; then
    KAITO_PLANE_KEY=$PLANE_API_KEY; KAITO_PLANE_WORKSPACE=$PLANE_WORKSPACE; KAITO_PLANE_BASE=${PLANE_BASE_URL:-}; SRC=env; return 0
  fi
  KAITO_PLANE_KEY=$(envval PLANE_API_KEY "$K/.env"); KAITO_PLANE_WORKSPACE=$(envval PLANE_WORKSPACE "$K/.env")
  KAITO_PLANE_BASE=$(envval PLANE_BASE_URL "$K/.env")
  if [ -n "$KAITO_PLANE_KEY" ] && [ -n "$KAITO_PLANE_WORKSPACE" ]; then SRC="$K/.env"; return 0; fi
  KAITO_PLANE_KEY=""; KAITO_PLANE_WORKSPACE=""; KAITO_PLANE_BASE=""; return 1
}
# Linear: LINEAR_API_KEY, a personal API key.
creds_linear() {
  if [ -n "${LINEAR_API_KEY:-}" ]; then KAITO_LINEAR_KEY=$LINEAR_API_KEY; SRC=env; return 0; fi
  for f in "$K/.env" "$HOME/.config/linear/.env"; do
    KAITO_LINEAR_KEY=$(envval LINEAR_API_KEY "$f")
    if [ -n "$KAITO_LINEAR_KEY" ]; then SRC=$f; return 0; fi
  done
  KAITO_LINEAR_KEY=""; return 1
}
creds() { "creds_$mgr"; }
# node gets credentials from env, never argv
need_creds() {
  case "$mgr" in
    plane) creds || die "no Plane credentials: run 'sh $here/kaito-tasks.sh login' in a terminal, or use the Plane MCP (references/tasks.md)"
           export KAITO_PLANE_KEY KAITO_PLANE_WORKSPACE KAITO_PLANE_BASE ;;
    linear) creds || die "no Linear credentials: run 'sh $here/kaito-tasks.sh login' in a terminal, or use the Linear MCP (references/tasks.md)"
            export KAITO_LINEAR_KEY ;;
    *) creds || die "no Trello credentials: run 'sh $here/kaito-tasks.sh login' in a terminal"
       export KAITO_TRELLO_KEY KAITO_TRELLO_TOKEN ;;
  esac
}
remote() { case "$mgr" in trello|plane|linear) return 0 ;; esac; return 1; }
# Before a secret prompt: echo off, and back on however the script ends.
noecho() {
  old=$(stty -g)
  trap 'stty "$old" 2>/dev/null || :' EXIT
  trap 'stty "$old" 2>/dev/null || :; exit 130' INT TERM
  stty -echo
}
need_board() { [ -n "$B" ] || die "no board mapped for this project: run kaito-tasks.sh boards, then map <boardId>"; }

# The node side lives in kaito-tasks.mjs and providers/<manager>.mjs.
J() { node "$here/kaito-tasks.mjs" "$@"; }

case "$cmd" in
  status)
    echo "manager: $mgr"
    if remote; then
      if creds; then echo "credentials: yes ($SRC)"; else echo "credentials: no"; fi
      if [ -n "$board" ] || [ -z "$tm" ]; then echo "${board:-board: none}"; fi
    else echo "notes: $D"; fi
    grep -q -E '^(tracker|tracking): ' "$pf" 2>/dev/null && node "$TK" "$pf" list
    c=$(cfg "$DK.consent")
    if [ -n "$c" ]; then echo "discovery: $c $(cfg "$DK.at") ($(node "$here/kaito-json.mjs" each "$CFG" "$DK.boards" | tr '\n' ' ' | sed 's/ $//'))"
    else echo "discovery: not asked"; fi
    s=$(cfg tasks.state); echo "onboarding: ${s:-pending}"
    ;;
  login)
    remote || die "login is for Trello, Plane and Linear; the manager is $mgr"
    [ -t 0 ] && [ -t 1 ] || die "login reads secrets, so run it in a terminal: sh $here/kaito-tasks.sh login"
    if [ "$mgr" = plane ]; then
      cat <<EOF
Plane needs your workspace slug and a personal API key.
  1. The slug is the part after the host in your Plane URL: https://app.plane.so/<slug>/...
  2. In Plane open Profile settings, Personal Access Tokens, and add a token. Copy it.
They are saved to $K/.env (mode 600). The key is not echoed.
The Plane MCP is optional and separate: without a key helpmekaito can use it instead (see references/tasks.md).

EOF
      printf "Workspace slug: "; IFS= read -r ws || ws=""
      printf "Plane URL, only if self-hosted (Enter for Plane Cloud): "; IFS= read -r burl || burl=""
      noecho
      printf "Plane API key: "; IFS= read -r key || key=""; echo
      stty "$old"
      case "$ws" in ""|*[!A-Za-z0-9_-]*) die "that does not look like a workspace slug; nothing saved" ;; esac
      case "$key" in ""|*[!A-Za-z0-9_-]*) die "that does not look like a Plane API key; nothing saved" ;; esac
      case "$burl" in ""|https://*|http://localhost*|http://127.0.0.1*) ;; *) die "the Plane URL must start with https://; nothing saved" ;; esac
      case "$burl" in *[[:space:]\"\']*) die "bad Plane URL; nothing saved" ;; esac
      u=$(KAITO_PLANE_KEY=$key KAITO_PLANE_WORKSPACE=$ws KAITO_PLANE_BASE=$burl J me 2>/dev/null) || die "Plane did not accept that key; nothing saved"
      KAITO_PLANE_KEY=$key KAITO_PLANE_WORKSPACE=$ws KAITO_PLANE_BASE=$burl J boards >/dev/null 2>&1 || die "that key cannot read workspace $ws; nothing saved"
      (
        umask 077; mkdir -p "$K"; t="$K/.env.$$.tmp"
        { grep -v -E '^(export )?(PLANE_API_KEY|PLANE_WORKSPACE|PLANE_BASE_URL)=' "$K/.env" 2>/dev/null || :
          printf 'PLANE_API_KEY=%s\nPLANE_WORKSPACE=%s\n' "$key" "$ws"
          [ -z "$burl" ] || printf 'PLANE_BASE_URL=%s\n' "$burl"; } > "$t"
        chmod 600 "$t"; mv "$t" "$K/.env"
      )
      node "$here/kaito-json.mjs" set "$CFG" tasks.steps.credentials true
      echo "saved Plane credentials for $u (workspace $ws) to $K/.env"
      exit 0
    fi
    if [ "$mgr" = linear ]; then
      cat <<EOF
Linear needs a personal API key.
  In Linear open Settings, Security & access, Personal API keys (https://linear.app/settings/account/security),
  create a key and copy it.
It is saved to $K/.env (mode 600). The key is not echoed.
The Linear MCP is optional and separate: without a key helpmekaito can use it instead (see references/tasks.md).

EOF
      noecho
      printf "Linear API key: "; IFS= read -r key || key=""; echo
      stty "$old"
      case "$key" in ""|*[!A-Za-z0-9_]*) die "that does not look like a Linear API key; nothing saved" ;; esac
      u=$(KAITO_LINEAR_KEY=$key J me 2>/dev/null) || die "Linear did not accept that key; nothing saved"
      (
        umask 077; mkdir -p "$K"; t="$K/.env.$$.tmp"
        { grep -v -E '^(export )?LINEAR_API_KEY=' "$K/.env" 2>/dev/null || :
          printf 'LINEAR_API_KEY=%s\n' "$key"; } > "$t"
        chmod 600 "$t"; mv "$t" "$K/.env"
      )
      node "$here/kaito-json.mjs" set "$CFG" tasks.steps.credentials true
      echo "saved Linear credentials for $u to $K/.env"
      exit 0
    fi
    cat <<EOF
Trello needs an API key and a token.
  1. Open https://trello.com/power-ups/admin and make a new Power-Up (any name, any workspace).
  2. Open it, go to API key, and generate a new API key. Copy the key.
  3. On that page, follow the link to generate a token (the authorize link next to the key). Allow, then copy the token.
They are saved to $K/.env (mode 600). Nothing is echoed.
The Trello MCP is optional and separate: add it from your agent's MCP or connector settings (see references/tasks.md).

EOF
    noecho
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
  boards) remote || die "boards is for Trello, Plane and Linear"; need_creds; J boards ;;
  modules)
    [ "$mgr" = plane ] || die "modules is for Plane"
    id=${2:-}; case "$id" in ""|*[!A-Za-z0-9-]*) die "usage: kaito-tasks.sh modules <projectId>" ;; esac
    need_creds; J modules "$id" ;;
  projects)
    [ "$mgr" = linear ] || die "projects is for Linear"
    id=${2:-}; case "$id" in ""|*[!A-Za-z0-9-]*) die "usage: kaito-tasks.sh projects <teamId>" ;; esac
    need_creds; J projects "$id" ;;
  structure)
    case "${2:-}:${3:-}" in put:plane|put:linear) ;; *) die "usage: kaito-tasks.sh structure put plane|linear  (JSON on stdin)" ;; esac
    [ "$mgr" = "$3" ] || die "structure put $3 is for the $3 manager; the manager is $mgr"
    if off; then exit 0; fi
    J structure-put ;;
  consent)
    case "${2:-}" in yes|no) ;; *) die "usage: kaito-tasks.sh consent yes|no <boardId>..." ;; esac
    a=$2; shift 2
    [ "$a" = no ] || [ $# -gt 0 ] || die "consent yes needs the board ids to discover"
    list=""; for b in "$@"; do
      case "$b" in ""|*[!A-Za-z0-9-]*) die "bad board id $b" ;; esac
      list="$list${list:+,}\"$b\""
    done
    node "$here/kaito-json.mjs" set "$CFG" "$DK" "{\"consent\":\"$a\",\"boards\":[$list],\"at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
    [ "$a" = yes ] || node "$here/kaito-json.mjs" set "$CFG" tasks.steps.discovery true  # yes: done once discover succeeds
    echo "discovery consent: $a${list:+ for $*}"
    ;;
  discover)
    remote || die "discover is for Trello, Plane and Linear"
    if off; then exit 0; fi
    [ "$(cfg "$DK.consent")" = yes ] || die "no discovery consent: ask first, then run kaito-tasks.sh consent yes <boardId>..."
    bs=$(node "$here/kaito-json.mjs" each "$CFG" "$DK.boards")
    [ -n "$bs" ] || die "consent lists no boards"
    need_creds
    # shellcheck disable=SC2086  # ids are checked to [A-Za-z0-9-] by consent
    J discover $bs
    node "$here/kaito-json.mjs" set "$CFG" tasks.steps.discovery true
    ;;
  map)
    remote || die "map is for Trello, Plane and Linear"
    if [ -n "$boot" ] && off; then exit 0; fi
    id=${2:-}
    if [ "$mgr" != trello ]; then
      u="<teamId>[/<projectId>]"; [ "$mgr" = linear ] || u="<projectId>[/<moduleId>]"
      case "$id" in ""|*[!A-Za-z0-9/-]*|*/*/*|/*|*/) die "usage: kaito-tasks.sh map $u" ;; esac
    else case "$id" in ""|*[!A-Za-z0-9]*) die "usage: kaito-tasks.sh map <boardId>" ;; esac; fi
    need_creds
    name=$(J board-name "$id")  # fetched before the lock: never hold it across a network call
    old=$(node "$TK" "$pf" select "$mgr" 2>/dev/null | sed -n 2p) || old=""
    # Linear trusts its cache (a cached issue skips the team and project checks), so a new id drops the old cache.
    # Conflict copies stay: they hold the user's own edits.
    drop_cache() {
      [ "$mgr" = linear ] && [ "$old" != "$id" ] && [ -d "$D" ] || return 0
      find "$D" -mindepth 1 -maxdepth 1 ! -name conflicts -exec rm -rf {} +
    }
    # A project already on tracker lines, or on an old board line of another manager, keeps them:
    # map updates this manager's line and every other tracker and setting stays.
    if grep -q '^tracker: ' "$pf" 2>/dev/null || grep '^board: ' "$pf" 2>/dev/null | grep -q -v -e "^board: $mgr " -e '^board: none'; then tk_write add "$mgr" "$id" "$name"; drop_cache; exit 0; fi
    (
      mkdir -p "$M/projects" || die "could not open memory"
      mlock
      index_line
      { grep -v -e '^board:' -e '^tracking: never' "$pf" 2>/dev/null || :; echo "board: $mgr $id $name"; } > "$pf.$$.tmp"
      mv "$pf.$$.tmp" "$pf"
    ) || die "could not write $pf"
    if [ -x "$here/kaito-obsidian.sh" ]; then "$here/kaito-obsidian.sh" push "projects/$MS.md" >/dev/null 2>&1 || :; fi
    drop_cache
    echo "board: $mgr $id $name"
    ;;
  pull)
    if off; then exit 0; fi
    if [ "$mgr" = obsidian ]; then echo "obsidian notes are the source; nothing to pull"; exit 0; fi
    need_board; need_creds
    # Structure memory refreshes itself: a pull re-runs discovery when the map is older than tasks.structure_ttl_hours (default 24).
    if [ "$(cfg "$DK.consent")" = yes ]; then
      KAITO_DISCOVER_IDS=$(node "$here/kaito-json.mjs" each "$CFG" "$DK.boards" | tr '\n' ' ')
      KAITO_TTL_HOURS=$(cfg tasks.structure_ttl_hours); export KAITO_DISCOVER_IDS KAITO_TTL_HOURS
    fi
    stamp check; J pull; stamp write ;;
  list)
    # Several scripted trackers and none named: list each under its own heading. Each one answers for its own tracking setting.
    if [ -z "$want" ] && [ "$(printf '%s\n' $scripted | grep -c .)" -gt 1 ]; then
      for t in $scripted; do echo "## $t"; sh "$0" --tracker "$t" list; done
    elif off; then exit 0
    else stamp check; J list; fi ;;
  add|check|uncheck|rename|move|comment|link|done|reopen|item)
    op=$cmd; shift
    if [ "$op" = item ]; then [ "${1:-}" = add ] || die "usage: kaito-tasks.sh item add <task> \"<text>\""; op=item-add; shift; fi
    if off >&2; then exit 1; fi
    if remote; then need_board; need_creds; fi
    stamp check; rc=0; J op "$op" "$@" || rc=$?; stamp write; exit "$rc"
    ;;
  *) echo "$USAGE" >&2; exit 2 ;;
esac
