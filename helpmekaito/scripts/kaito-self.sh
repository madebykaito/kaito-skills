#!/bin/sh
# The install looks after itself: version, update check, upgrade and uninstall.
# Usage: kaito-self.sh version | mode [auto|ask|off] | check [--force] | auto | snooze | upgrade
#        | uninstall [--purge] [--yes]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
K="${KAITO_HOME:-$HOME/.kaito}"
J="$here/kaito-json.mjs"
S="$K/state.json"
C="$K/update-check.json"

usage() {
  echo "usage: kaito-self.sh version | mode [auto|ask|off] | check [--force] | auto | snooze | upgrade | uninstall [--purge] [--yes]" >&2
  exit 2
}
jget() { node "$J" get "$1" "$2" 2>/dev/null | tr -d '"'; }
count() { node "$J" each "$S" "$1" 2>/dev/null | grep -c . || :; }
now() { echo "$(($(date +%s) * 1000))"; }
num() { case "$1" in ""|*[!0-9]*) return 1 ;; esac; }
by_version() { sort -t. -k1,1n -k2,2n -k3,3n; }

installed() {
  v=$(jget "$S" version)
  if [ -z "$v" ] && [ -f "$K/store/VERSION" ]; then v=$(tr -cd '0-9A-Za-z.+-' < "$K/store/VERSION"); fi
  echo "${v:-unknown}"
}
mode() {
  m=$(jget "$K/config.json" update.mode)
  case "$m" in ask|off) echo "$m" ;; *) echo auto ;; esac
}
# newer <a> <b>: b is a higher x.y.z than a, compared number by number (1.10.0 > 1.9.0).
newer() {
  for v in "$1" "$2"; do
    case "$v" in *[!0-9.]*|*.*.*.*) return 1 ;; *?.*?.*?) ;; *) return 1 ;; esac
  done
  [ "$1" != "$2" ] && [ "$(printf '%s\n' "$1" "$2" | by_version | tail -n 1)" = "$2" ]
}
# git with a time limit and no prompt, so a dead network never hangs a session.
# Through node: GNU timeout is not on macOS or Git Bash, and busybox has its own.
tgit() {
  ms=$1; shift
  GIT_TERMINAL_PROMPT=0 node -e 'try { require("child_process").execFileSync("git", process.argv.slice(2), { timeout: +process.argv[1], stdio: "inherit" }) } catch { process.exit(1) }' "$ms" "$@"
}
has_clone() { [ -n "$repo" ] && [ -e "$repo/.git" ] && git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; }
lookup() {
  has_clone || return 0
  tgit 5000 -C "$repo" ls-remote --tags --refs origin 'v*' 2>/dev/null |
    sed -n 's|.*refs/tags/v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$|\1|p' | by_version | tail -n 1
}
# latest [force]: sets L to the newest release, from the cache when it is fresh. A failed lookup is cached too (L empty).
latest() {
  at=$(jget "$C" at); ttl=${KAITO_UPDATE_TTL_HOURS:-24}
  if [ "${1:-}" != force ] && num "$at" && num "$ttl" && [ $(($(now) - at)) -lt $((ttl * 3600000)) ]; then
    L=$(jget "$C" latest); return 0
  fi
  L=$(lookup)
  [ -d "$K" ] || return 0
  node "$J" check "$C" 2>/dev/null || rm -f "$C"
  node "$J" set "$C" at "$(now)" && node "$J" set "$C" latest "\"$L\"" && node "$J" del "$C" failed && node "$J" del "$C" trying || :
}

changes() {  # up to 8 bullets of the "## [<version>]" section
  awk -v h="## [$1]" 'index($0, h) == 1 { on = 1; next } /^## / { on = 0 }
    on && /^- / { print substr($0, 1, 160); if (++n == 8) exit }' "$repo/CHANGELOG.md" 2>/dev/null || :
}
# do_upgrade <installed> <latest>: returns 1 with the reason in $why. Callers test it, so no set -e in here.
do_upgrade() {
  a=$1 b=$2 log="$K/upgrade.log"
  has_clone || { why="no clone recorded"; return 1; }
  [ -z "$(git -C "$repo" status --porcelain 2>/dev/null)" ] || { why="clone has uncommitted changes"; return 1; }
  br=$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null) || br=detached
  def=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || def=""
  def=${def#origin/}
  if [ -z "$def" ]; then case "$br" in main|master) def=$br ;; *) def=main ;; esac; fi
  [ "$br" = "$def" ] || { why="clone is on branch $br, not $def"; return 1; }
  : > "$log" || { why="cannot write $log"; return 1; }
  tgit 120000 -C "$repo" fetch --tags origin >> "$log" 2>&1 || { why="could not fetch"; return 1; }
  # The release tag, never the tip of main: main may hold unreleased work.
  git -C "$repo" merge --ff-only "v$b" >> "$log" 2>&1 || { why="cannot fast-forward to v$b"; return 1; }
  # A clone already past the tag would install unreleased work under the release's name.
  [ "$(git -C "$repo" rev-parse HEAD)" = "$(git -C "$repo" rev-parse "v$b^{commit}")" ] || { why="clone is ahead of v$b"; return 1; }
  set --
  # The same gstack choice as the install: the config switch, or a --no-gstack run recorded in state.
  [ "$(jget "$K/config.json" gstack)" != false ] && [ "$(jget "$S" gstack)" != false ] || set -- --no-gstack
  # shellcheck disable=SC2086  # KAITO_SELF_SETUP_ARGS is a list of flags
  sh "$repo/setup" --upgrade "$@" ${KAITO_SELF_SETUP_ARGS:-} >> "$log" 2>&1 ||
    { why="setup failed, see $log (the clone is already at v$b)"; return 1; }
  echo "upgraded: $a -> $b"
  changes "$b"
  echo "new sessions use the new skills"
}

# run_upgrade <installed> <latest>: the unattended upgrade; its outcome lands in upgrade.result for auto to print.
run_upgrade() {
  {
    if ! do_upgrade "$1" "$2"; then
      echo "upgrade skipped: $why"
      echo "to upgrade by hand: cd $repo && git pull && ./setup"
      node "$J" set "$C" failed "\"$2\"" 2>/dev/null || :
    fi
  } > "$K/upgrade.result.tmp" 2>&1
  node "$J" del "$C" trying 2>/dev/null || :
  mv "$K/upgrade.result.tmp" "$K/upgrade.result"
}

uninstall() {
  purge=0 yes=0
  for x in "$@"; do
    case "$x" in --purge) purge=1 ;; --yes) yes=1 ;; *) usage ;; esac
  done
  if [ "$yes" = 0 ]; then
    n=$(count links); e=$(($(count managed_overrides) + $(count managed_permissions)))
    [ -z "$(jget "$S" managed_hook)" ] || e=$((e + 1))
    t=$(count taken_over)
    p=$(node -e 'try { console.log(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).disabled_plugins || {}).join(", ")) } catch {}' "$S")
    echo "would remove:"
    [ "$n" = 0 ] || echo "  $n skill links"
    [ ! -d "$K/store" ] || echo "  the store ($K/store)"
    [ "$e" = 0 ] || echo "  $e settings entries (skillOverrides, permissions, hook)"
    [ "$t" = 0 ] && [ -z "$p" ] || echo "would restore:"
    [ "$t" = 0 ] || echo "  $t skills moved aside by setup"
    [ -z "$p" ] || echo "  plugins: $p"
    if [ "$purge" = 1 ]; then echo "  and delete $K with config, memory and task credentials"
    else echo "keeps: $K (config, memory, task credentials)"; fi
    echo "run again with --yes to do it"
    return 0
  fi
  set -- --uninstall
  [ "$purge" = 0 ] || set -- --uninstall --purge
  if [ -f "$K/store/setup" ]; then
    # The store's copy is the installed release's own setup: the clone may be on another version that
    # does not know what this one moved aside. The store is deleted during the run, so it runs from a copy.
    tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
    cp "$K/store/setup" "$tmp"
    out=$(KAITO_SETUP_REPO="$K/store" sh "$tmp" "$@" 2>&1) || { printf '%s\n' "$out" >&2; exit 1; }
  elif [ -n "$repo" ] && [ -f "$repo/setup" ]; then
    out=$(sh "$repo/setup" "$@" 2>&1) || { printf '%s\n' "$out" >&2; exit 1; }
  else
    echo "kaito-self: no setup found in $K/store or in the clone" >&2; exit 1
  fi
  rm -f "$C" "$K/upgrade.log" "$K/upgrade.result"
  echo "uninstalled kaito-skills"
  printf '%s\n' "$out" | grep '^kaito: .* \(is in use\|not deleting\)' || :  # what setup could not put back or delete
  [ ! -d "$K" ] || echo "kept: $K"
  echo "start a new session; this one still has the old skills loaded"
}

# Upgrade and uninstall replace or delete this file while it runs. sh reads a script as it goes,
# so everything runs from main(), called on the last line when the whole file is already read.
main() {
  repo=$(jget "$S" repo)
  A=$(installed)
  case "${1:-}" in
    version) echo "$A" ;;
    mode)
      case "${2:-}" in
        "") mode ;;
        auto|ask|off) node "$J" set "$K/config.json" update.mode "\"$2\""; echo "updates: $2" ;;
        *) usage ;;
      esac ;;
    check)
      case "${2:-}" in --force) latest force ;; "") latest ;; *) usage ;; esac
      if newer "$A" "$L"; then echo "update: $A -> $L"; fi ;;
    snooze)
      latest
      newer "$A" "$L" || { echo "nothing to snooze"; return 0; }
      node "$J" set "$C" snooze "{\"version\":\"$L\",\"until\":$(($(now) + 604800000))}"
      echo "snoozed: $L for 7 days" ;;
    auto)
      # Runs at the start of every task: nothing here may fail the task or ask a question.
      # A background upgrade an earlier task started has finished: say so now.
      if [ -f "$K/upgrade.result" ]; then cat "$K/upgrade.result"; rm -f "$K/upgrade.result"; fi
      m=$(mode)
      [ "$m" != off ] || return 0
      latest 2>/dev/null || return 0
      newer "$A" "$L" || return 0
      until=$(jget "$C" snooze.until)
      if [ "$(jget "$C" snooze.version)" = "$L" ] && num "$until" && [ "$(now)" -lt "$until" ]; then return 0; fi
      if [ "$m" = ask ]; then echo "update: $A -> $L"; return 0; fi
      [ "$(jget "$C" failed)" != "$L" ] || return 0
      # One upgrade at a time across sessions; a run that died is retried after an hour.
      t=$(jget "$C" trying)
      if num "$t" && [ $(($(now) - t)) -lt 3600000 ]; then return 0; fi
      node "$J" set "$C" trying "$(now)" 2>/dev/null || return 0
      # Setup can take minutes (gstack build), so it never holds up the task: the next task reports it.
      if [ "${KAITO_SELF_FOREGROUND:-0}" = 1 ]; then
        echo "upgrading kaito-skills $A -> $L"
        run_upgrade "$A" "$L"; cat "$K/upgrade.result"; rm -f "$K/upgrade.result"
      else
        nohup sh "$here/kaito-self.sh" _run "$A" "$L" >/dev/null 2>&1 &
        echo "upgrading kaito-skills $A -> $L in the background"
      fi ;;
    _run) run_upgrade "$2" "$3" ;;
    upgrade)
      has_clone || { echo "upgrade skipped: no clone recorded"; exit 1; }
      latest force
      [ -n "$L" ] || { echo "upgrade skipped: could not fetch"; exit 1; }
      newer "$A" "$L" || { echo "up to date: $A"; return 0; }
      do_upgrade "$A" "$L" || { echo "upgrade skipped: $why"; exit 1; } ;;
    uninstall) shift; uninstall "$@" ;;
    *) usage ;;
  esac
}
main "$@"
