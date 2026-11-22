#!/bin/sh
# Install and uninstall into a throwaway HOME with the real setup, then check nothing is left.
# Usage: tests/smoke.sh   (CI runs it on every platform; never touches your real home)
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
tmp=${TMPDIR:-/tmp}; h=$(mktemp -d "${tmp%/}/kaito-smoke.XXXXXX")
trap 'rm -rf "$h"' EXIT
HOME=$h; export HOME; unset KAITO_HOME CODEX_HOME XDG_CONFIG_HOME KAITO_ANSWERS
fail() { echo "smoke: $*" >&2; exit 1; }

"$repo/setup" --yes --no-gstack --no-codegraph
for s in helpmekaito better-ui ponytail; do
  [ -L "$h/.claude/skills/$s" ] || fail "no link for $s"
  [ -f "$h/.claude/skills/$s/SKILL.md" ] || fail "link for $s does not resolve"
done
[ -L "$h/.agents/skills/helpmekaito" ] || fail "no Codex link"
n=$(ls "$h/.claude/skills" | wc -l | tr -d ' ')
[ "$n" -gt 100 ] || fail "only $n Claude links"
node "$repo/helpmekaito/scripts/kaito-json.mjs" get "$h/.claude/settings.json" skillOverrides.better-ui | grep -q name-only ||
  fail "no name-only override"

mkdir "$h/project"
(
  cd "$h/project"
  mem="$h/.agents/skills/helpmekaito/scripts/kaito-mem.sh"
  lesson="Use the smoke fixture for installed memory checks"
  [ "$(printf '%s\n' "$lesson" | "$mem" capture convention)" = saved ] || fail "installed capture failed"
  [ "$(printf '%s\n' "$lesson" | "$mem" capture convention)" = already_present ] || fail "installed capture repeated a lesson"
  "$mem" where | grep -Eq "^learn: convention 1 [0-9-]+ $lesson$" || fail "installed capture was not recalled"
  "$mem" where task >/dev/null || fail "installed task start failed"
  task_output=$("$mem" where task) || fail "installed second task start failed"
  printf '%s\n' "$task_output" | grep -q '^closeout_missed:' || fail "missing closeout reminder"
  closeout_output=$("$mem" closeout nothing_to_save) || fail "installed closeout failed"
  [ "$closeout_output" = nothing_to_save ] || fail "closeout did not report nothing_to_save"
  task_output=$("$mem" where task) || fail "installed task start after closeout failed"
  if printf '%s\n' "$task_output" | grep -q '^closeout_missed:'; then fail "closeout reminder remained after closeout"; fi
)

"$repo/setup" --yes --no-gstack --no-codegraph >/dev/null  # a re-run changes nothing
[ "$(ls "$h/.claude/skills" | wc -l | tr -d ' ')" = "$n" ] || fail "re-run changed the links"

"$repo/setup" --uninstall
left=$(ls -A "$h/.claude/skills" "$h/.agents/skills" 2>/dev/null | grep -v ':$' | grep -v '^$' || true)
[ -z "$left" ] || fail "left behind: $left"
[ ! -e "$h/.kaito/store" ] || fail "store not removed"
echo "smoke ok ($n skills)"
