#!/bin/sh
. "$(dirname "$0")/lib.sh"
J="$REPO/helpmekaito/scripts/kaito-json.mjs"

g() { git -c user.name=t -c user.email=t@example.test -c init.defaultBranch=main -C "$R" "$@"; }
origin_git() { git -c user.name=t -c user.email=t@example.test -C "$fixture" --git-dir="$O" --work-tree="$fixture" "$@"; }
# A git clone of the repo at release <version> (default 1.4.0) with a local bare origin, installed.
mk_install() {
  mk_home
  # Hooks can export paths into the caller's Git directory and object store.
  unset $(git rev-parse --local-env-vars)
  fixture="$(mktemp -d)"
  R="$(mktemp -d)/kaito-skills"
  node "$REPO/helpmekaito/scripts/kaito-sync.mjs" mirror -x .git -x .codegraph -x ./gstack -x ./.superpowers -x node_modules "$REPO" "$fixture" || exit 1
  V=${1:-1.4.0}
  echo "$V" > "$fixture/VERSION"
  O="$(mktemp -d)/origin.git"
  git init -q --bare --initial-branch=main "$O" &&
    origin_git add -A && origin_git commit -qm "$V" && origin_git tag "v$V" &&
    git clone -q --no-local "$O" "$R" && g remote set-head origin -d || exit 1
  KAITO_SELF_SETUP_ARGS="--no-gstack --no-codegraph"; export KAITO_SELF_SETUP_ARGS
  KAITO_SELF_FOREGROUND=1; export KAITO_SELF_FOREGROUND  # the upgrade runs inline, so a test can read its result
  "$R/setup" --yes --no-gstack --no-codegraph > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }
  [ -z "$(g status --porcelain)" ] || { echo "  setup left the clone dirty"; g status --porcelain; exit 1; }
  SELF="$KAITO_HOME/store/helpmekaito/scripts/kaito-self.sh"
}
self() { sh "$SELF" "$@"; }
# Publish in the origin's own object store, leaving the installed clone untouched.
release() {
  echo "$1" > "$fixture/VERSION"
  printf '# Changelog\n\n## [%s] - 2026-01-01\n\n### Added\n\n- first change in %s\n- second change\n\n## [1.0.0]\n\n- old change\n' "$1" "$1" > "$fixture/CHANGELOG.md"
  origin_git commit -qam "$1" && origin_git tag "v$1" || exit 1
}
state_version() { node "$J" get "$KAITO_HOME/state.json" version; }

test_version_and_mode() {
  mk_install
  assert_eq "$(self version)" 1.4.0 version
  assert_eq "$(self mode)" auto default_mode
  assert_eq "$(self mode ask)" "updates: ask" set_mode
  assert_eq "$(self mode)" ask mode_kept
  assert_eq "$(node "$J" get "$KAITO_HOME/config.json" update.mode)" '"ask"' config
  rc=0; self mode sometimes 2> /dev/null || rc=$?
  assert_eq "$rc" 2 bad_mode
  node "$J" del "$KAITO_HOME/state.json" version
  assert_eq "$(self version)" 1.4.0 version_from_store
  rm "$KAITO_HOME/store/VERSION"
  assert_eq "$(self version)" unknown version_unknown
  assert_eq "$(self check --force)" "" unknown_never_updates
}

test_check_notice_and_cache() {
  mk_install
  assert_eq "$(self check)" "" up_to_date
  release 1.5.0
  assert_eq "$(self check)" "" cached_answer
  assert_eq "$(self check --force)" "update: 1.4.0 -> 1.5.0" notice
  assert_eq "$(node "$J" get "$KAITO_HOME/update-check.json" latest)" '"1.5.0"' cache_file
  g remote remove origin
  assert_eq "$(self check)" "update: 1.4.0 -> 1.5.0" from_cache
  assert_eq "$(self check --force)" "" lookup_failed_silent
  assert_eq "$(node "$J" get "$KAITO_HOME/update-check.json" latest)" '""' failure_cached
  rm -rf "$R"
  self check --force > "$HOME/o" 2>&1 || { echo "  check failed without a clone"; exit 1; }
  assert_eq "$(cat "$HOME/o")" "" no_clone_silent
}

test_semver_is_numeric() {
  mk_install 1.9.0
  release 1.10.0
  g tag v1.9.5; g tag vnext; g push -q origin v1.9.5 vnext
  assert_eq "$(self check)" "update: 1.9.0 -> 1.10.0" highest
}

test_auto_upgrades_by_default() {
  mk_install; release 1.5.0
  mkdir -p "$R/.claude/worktrees"
  echo local > "$R/.claude/worktrees/keep.txt"
  self auto > "$HOME/o" 2>&1 || { cat "$HOME/o"; exit 1; }
  assert_eq "$(sed -n 1p "$HOME/o")" "upgrading kaito-skills 1.4.0 -> 1.5.0" first_line
  assert_eq "$(sed -n 2p "$HOME/o")" "upgraded: 1.4.0 -> 1.5.0" upgraded
  assert_eq "$(sed -n 3p "$HOME/o")" "- first change in 1.5.0" changelog
  assert_eq "$(sed -n 4p "$HOME/o")" "- second change" changelog_2
  assert_eq "$(sed -n 5p "$HOME/o")" "new sessions use the new skills" last_line
  assert_eq "$(state_version)" '"1.5.0"' state
  assert_eq "$(cat "$KAITO_HOME/store/VERSION")" 1.5.0 store
  assert_eq "$(cat "$R/.claude/worktrees/keep.txt")" local untracked_kept
  assert_file "$KAITO_HOME/upgrade.log"
  assert_link "$HOME/.claude/skills/helpmekaito" "$KAITO_HOME/store/"
  assert_eq "$(self auto)" "" quiet_after
  assert_eq "$(self upgrade)" "up to date: 1.5.0" explicit
}

test_auto_ask_and_off() {
  mk_install; release 1.5.0
  self mode ask > /dev/null
  assert_eq "$(self auto)" "update: 1.4.0 -> 1.5.0" ask_prints
  assert_eq "$(state_version)" '"1.4.0"' ask_no_upgrade
  self mode off > /dev/null
  rm "$KAITO_HOME/update-check.json"
  assert_eq "$(self auto)" "" off_silent
  assert_no "$KAITO_HOME/update-check.json"  # off does no lookup at all
}

test_snooze_one_version() {
  mk_install; release 1.5.0
  self mode ask > /dev/null
  assert_eq "$(self auto)" "update: 1.4.0 -> 1.5.0" before
  assert_eq "$(self snooze)" "snoozed: 1.5.0 for 7 days" snooze
  assert_eq "$(node "$J" get "$KAITO_HOME/update-check.json" latest)" '"1.5.0"' keys_kept
  assert_eq "$(self auto)" "" snoozed
  assert_eq "$(KAITO_UPDATE_TTL_HOURS=0 self auto)" "" snoozed_after_recheck
  self mode auto > /dev/null
  assert_eq "$(self auto)" "" snoozed_in_auto_mode
  self mode ask > /dev/null
  release 1.6.0
  assert_eq "$(KAITO_UPDATE_TTL_HOURS=0 self auto)" "update: 1.4.0 -> 1.6.0" newer_shows
}

test_auto_retries_after_tracked_changes() {
  mk_install; release 1.5.0
  echo mine >> "$R/README.md"
  rc=0; out=$(self upgrade) || rc=$?
  assert_eq "$out" "upgrade skipped: clone has uncommitted changes: README.md" dirty
  assert_eq "$rc" 1 dirty_exit
  assert_eq "$(self auto | sed -n 2p)" "$out" auto_dirty
  g add README.md
  assert_eq "$(self auto | sed -n 2p)" "$out" auto_staged
  assert_eq "$(node "$J" get "$KAITO_HOME/update-check.json" failed)" "" no_failed_mark
  assert_eq "$(state_version)" '"1.4.0"' untouched
  g checkout -q HEAD -- README.md
  assert_eq "$(self auto | sed -n 2p)" "upgraded: 1.4.0 -> 1.5.0" retried
  assert_eq "$(state_version)" '"1.5.0"' state
}

test_upgrade_refuses_unsafe_clone() {
  mk_install; release 1.5.0
  g checkout -q -b feature
  rc=0; out=$(self upgrade) || rc=$?
  assert_eq "$out" "upgrade skipped: clone is on branch feature, not main" branch
  assert_eq "$rc" 1 branch_exit
  # auto reports the same, exits 0 and leaves that version alone until the next daily check
  self auto > "$HOME/o" 2>&1 || { echo "  auto must not fail"; cat "$HOME/o"; exit 1; }
  assert_eq "$(sed -n 1p "$HOME/o")" "upgrading kaito-skills 1.4.0 -> 1.5.0" auto_1
  assert_eq "$(sed -n 2p "$HOME/o")" "upgrade skipped: clone is on branch feature, not main" auto_2
  assert_eq "$(sed -n 3p "$HOME/o")" "to upgrade by hand: cd $(cd "$R" && pwd -P) && git pull && ./setup" auto_3
  assert_eq "$(self auto)" "" failed_not_retried
  assert_eq "$(state_version)" '"1.4.0"' untouched
  # origin/HEAD names the default branch when it is set
  g checkout -q main; g branch -q -m trunk
  rc=0; out=$(self upgrade) || rc=$?
  assert_eq "$out" "upgrade skipped: clone is on branch trunk, not main" fallback_default
  g remote set-head origin main
  g branch -q -m main; g checkout -q -b other
  assert_eq "$(self upgrade || :)" "upgrade skipped: clone is on branch other, not main" origin_head
  g checkout -q main
  assert_eq "$(KAITO_UPDATE_TTL_HOURS=0 self auto | sed -n 2p)" "upgraded: 1.4.0 -> 1.5.0" retried_after_recheck
}

test_upgrade_lands_on_the_tag() {
  mk_install; release 1.5.0
  old=$(g rev-parse HEAD)
  g fetch -q origin && g reset -q --hard origin/main || exit 1
  echo 9.9.9 > "$R/VERSION"; echo later > "$R/LATER"; g add -A; g commit -qm "unreleased work"; g push -q origin main
  g reset -q --hard "$old"
  echo "upgrade skipped: clone has uncommitted changes: README.md" > "$KAITO_HOME/upgrade.result"
  self upgrade > "$HOME/o" 2>&1 || { cat "$HOME/o" "$KAITO_HOME/upgrade.log"; exit 1; }
  assert_eq "$(sed -n 1p "$HOME/o")" "upgraded: 1.4.0 -> 1.5.0" upgraded
  assert_eq "$(g rev-parse HEAD)" "$(g rev-parse 'v1.5.0^{commit}')" on_tag
  assert_no "$R/LATER"
  assert_eq "$(state_version)" '"1.5.0"' state
  assert_no "$KAITO_HOME/upgrade.result"
  assert_eq "$(self auto)" "" no_stale_result
}

test_upgrade_reports_failed_setup() {
  mk_install; release 1.5.0
  KAITO_SELF_SETUP_ARGS="--no-such-flag"
  rc=0; out=$(self upgrade) || rc=$?
  assert_eq "$out" "upgrade skipped: setup failed, see $KAITO_HOME/upgrade.log (the clone is already at v1.5.0)" reason
  assert_eq "$rc" 1 exit
  grep -q usage "$KAITO_HOME/upgrade.log" || { echo "  setup output not in the log"; exit 1; }
  assert_eq "$(state_version)" '"1.4.0"' state
  assert_eq "$(self auto | sed -n 2p)" "$out" auto_failed_setup
  assert_eq "$(node "$J" get "$KAITO_HOME/update-check.json" failed)" '"1.5.0"' failed_mark
}

test_uninstall_dry_run() {
  mk_install
  n=$(node "$J" each "$KAITO_HOME/state.json" links | grep -c .)
  self uninstall > "$HOME/o"
  assert_eq "$(sed -n 1p "$HOME/o")" "would remove:" header
  assert_eq "$(sed -n 2p "$HOME/o")" "  $n skill links" links
  assert_eq "$(sed -n 3p "$HOME/o")" "  the store ($KAITO_HOME/store)" store
  grep -q '^  [0-9]* settings entries (skillOverrides, permissions, hook)$' "$HOME/o" || { cat "$HOME/o"; exit 1; }
  grep -q '^would restore:$' "$HOME/o" && { echo "  nothing to restore here"; cat "$HOME/o"; exit 1; }
  grep -qxF "keeps: $KAITO_HOME (config, memory, task credentials)" "$HOME/o" || { cat "$HOME/o"; exit 1; }
  assert_eq "$(tail -n 1 "$HOME/o")" "run again with --yes to do it" last
  node "$J" set "$KAITO_HOME/state.json" taken_over '["a","b"]'
  node "$J" set "$KAITO_HOME/state.json" disabled_plugins '{"x@m":true,"y@m":false}'
  self uninstall --purge > "$HOME/o"
  grep -qx 'would restore:' "$HOME/o" || { cat "$HOME/o"; exit 1; }
  grep -qx '  2 skills moved aside by setup' "$HOME/o" || { cat "$HOME/o"; exit 1; }
  grep -qx '  plugins: x@m, y@m' "$HOME/o" || { cat "$HOME/o"; exit 1; }
  grep -qxF "  and delete $KAITO_HOME with config, memory and task credentials" "$HOME/o" || { cat "$HOME/o"; exit 1; }
  grep -q '^keeps:' "$HOME/o" && { cat "$HOME/o"; exit 1; }
  assert_file "$KAITO_HOME/store/better/better-ui/SKILL.md"
  assert_link "$HOME/.claude/skills/helpmekaito" "$KAITO_HOME/store/"
  assert_eq "$(state_version)" '"1.4.0"' state_kept
}

test_uninstall_with_the_clone() {
  mk_install
  self check > /dev/null
  self uninstall --yes > "$HOME/o" 2>&1 || { cat "$HOME/o"; exit 1; }
  assert_eq "$(sed -n 1p "$HOME/o")" "uninstalled kaito-skills" done
  assert_no "$KAITO_HOME/store"
  assert_no "$KAITO_HOME/update-check.json"
  assert_file "$R/setup"
}

test_uninstall_without_the_clone() {
  mk_install
  rm -rf "$R"
  self uninstall --yes > "$HOME/o" 2>&1 || { cat "$HOME/o"; exit 1; }
  assert_eq "$(sed -n 1p "$HOME/o")" "uninstalled kaito-skills" done
  assert_eq "$(sed -n 2p "$HOME/o")" "kept: $KAITO_HOME" kept
  assert_eq "$(sed -n 3p "$HOME/o")" "start a new session; this one still has the old skills loaded" session
  assert_no "$KAITO_HOME/store"
  assert_no "$KAITO_HOME/state.json"
  assert_no "$HOME/.claude/skills/helpmekaito"
  assert_file "$KAITO_HOME/config.json"
}

test_uninstall_purge() {
  mk_install
  rm -rf "$R"
  self uninstall --yes --purge > "$HOME/o" 2>&1 || { cat "$HOME/o"; exit 1; }
  assert_eq "$(sed -n 1p "$HOME/o")" "uninstalled kaito-skills" done
  assert_eq "$(sed -n 2p "$HOME/o")" "start a new session; this one still has the old skills loaded" session
  assert_no "$KAITO_HOME"
}

# By default the upgrade runs in the background and the next task start reports it.
test_auto_upgrades_in_the_background() {
  mk_install; release 1.5.0
  unset KAITO_SELF_FOREGROUND
  assert_eq "$(self auto)" "upgrading kaito-skills 1.4.0 -> 1.5.0 in the background" started
  i=0; while [ ! -f "$KAITO_HOME/upgrade.result" ] && [ $i -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
  assert_eq "$(state_version)" '"1.5.0"' upgraded
  assert_eq "$(self auto | sed -n 1p)" "upgraded: 1.4.0 -> 1.5.0" reported_next_time
  assert_eq "$(self auto)" "" reported_once
}

# A second session starting while the first upgrade runs does not start another.
test_auto_does_not_start_two_upgrades() {
  mk_install; release 1.5.0
  KAITO_UPDATE_TTL_HOURS=24 self check > /dev/null
  node "$J" set "$KAITO_HOME/update-check.json" trying "$(($(date +%s) * 1000))"
  assert_eq "$(self auto)" "" quiet_while_trying
  assert_eq "$(state_version)" '"1.4.0"' untouched
}

# A clone pulled past the tag holds unreleased work: it is not installed under the release's name.
test_upgrade_refuses_clone_ahead_of_tag() {
  mk_install; release 1.5.0
  g fetch -q --tags origin; g merge -q --ff-only v1.5.0
  echo extra > "$R/unreleased.txt"; g add -A; g commit -qm unreleased
  rc=0; out=$(self upgrade) || rc=$?
  assert_eq "$out" "upgrade skipped: clone is ahead of v1.5.0" ahead
  assert_eq "$(state_version)" '"1.4.0"' not_installed
}

# Installed with --no-gstack: the upgrade passes it on without being told.
test_upgrade_keeps_no_gstack_choice() {
  mk_install; release 1.5.0
  assert_eq "$(node "$J" get "$KAITO_HOME/state.json" gstack)" false recorded
  KAITO_SELF_SETUP_ARGS="--no-codegraph" self upgrade > "$HOME/o" 2>&1 || { cat "$HOME/o" "$KAITO_HOME/upgrade.log"; exit 1; }
  assert_no "$KAITO_HOME/store/gstack"
}

# The clone sits on an older release without the restore logic: uninstall still uses the installed setup.
test_uninstall_uses_the_installed_setup() {
  mk_install
  printf '#!/bin/sh\necho old setup ran; exit 1\n' > "$R/setup"
  self uninstall --yes > "$HOME/o" 2>&1 || { cat "$HOME/o"; exit 1; }
  assert_no "$KAITO_HOME/store"
}
