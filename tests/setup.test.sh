#!/bin/sh
. "$(dirname "$0")/lib.sh"
J="$REPO/helpmekaito/scripts/kaito-json.mjs"

# Copy the repo to a temp dir so setup never touches the real checkout.
mk_repo() {
  R="$(mktemp -d)/kaito-skills"
  rsync -a --exclude .git --exclude /gstack/ --exclude /.superpowers/ --exclude node_modules "$REPO/" "$R/"
}
run_setup() {
  "$R/setup" --yes --no-gstack --no-codegraph "$@" > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }
}
links() { for l in "$HOME/.claude/skills"/* "$HOME/.agents/skills"/*; do echo "$l -> $(readlink "$l")"; done; }
ov() { node "$J" get "$HOME/.claude/settings.json" "skillOverrides.$1"; }

test_setup_fresh_home() {
  mk_home; mk_repo; run_setup
  assert_file "$KAITO_HOME/store/better-ui/SKILL.md"
  assert_no "$KAITO_HOME/store/gstack"
  assert_link "$HOME/.claude/skills/better-ui" "$KAITO_HOME/store/"
  assert_link "$HOME/.claude/skills/helpmekaito" "$KAITO_HOME/store/"
  assert_eq "$(ov better-ui)" '"name-only"' override
  assert_eq "$(ov helpmekaito)" "" router_visible
  assert_eq "$(ls "$HOME/.agents/skills")" helpmekaito codex
  assert_eq "$(node "$J" get "$KAITO_HOME/config.json" codegraph.auto_index)" '"ask"' config
  assert_eq "$(node "$J" get "$KAITO_HOME/state.json" store_version)" '"unknown"' version
  node "$J" get "$KAITO_HOME/state.json" managed_overrides | grep -q '"better-ui"' || exit 1
}

test_hot_list() {
  mk_home; mk_repo
  mkdir -p "$KAITO_HOME"; echo '{"hot":["impeccable"]}' > "$KAITO_HOME/config.json"
  run_setup
  assert_eq "$(ov impeccable)" "" hot_visible
  assert_link "$HOME/.agents/skills/impeccable" "$KAITO_HOME/store/"
  assert_eq "$(node "$J" get "$KAITO_HOME/config.json" gstack)" "" config_kept
}

test_setup_idempotent() {
  mk_home; mk_repo; run_setup
  before=$(links)
  run_setup
  assert_eq "$(links)" "$before" same_links
  grep -qi '^skip\|error' "$HOME/out" && { cat "$HOME/out"; exit 1; }
  rm -rf "$R/better-ui"
  run_setup
  assert_no "$HOME/.claude/skills/better-ui"
  assert_no "$KAITO_HOME/store/better-ui"
  assert_eq "$(ov better-ui)" "" override_dropped
}

test_retires_repo_links() {
  mk_home; mk_repo
  mkdir -p "$HOME/.claude/skills" "$HOME/.codex/skills"
  ln -s "$R/better-ui" "$HOME/.claude/skills/better-ui"
  ln -s "$R/better-ui" "$HOME/.codex/skills/better-ui"
  run_setup
  assert_link "$HOME/.claude/skills/better-ui" "$KAITO_HOME/store/"
  assert_no "$HOME/.codex/skills/better-ui"
}

test_overrides_preserve_user_entries() {
  mk_home; mk_repo
  mkdir -p "$HOME/.claude"
  echo '{"model":"m","skillOverrides":{"mything":"off"}}' > "$HOME/.claude/settings.json"
  run_setup
  assert_eq "$(node "$J" get "$HOME/.claude/settings.json" model)" '"m"' model
  assert_eq "$(ov mything)" '"off"' user_entry
  assert_eq "$(ov better-ui)" '"name-only"' ours
}

test_user_changed_override_survives() {
  mk_home; mk_repo; run_setup
  node "$J" set "$HOME/.claude/settings.json" skillOverrides.better-ui '"off"'
  run_setup
  assert_eq "$(ov better-ui)" '"off"' rerun
  run_setup --uninstall
  assert_eq "$(ov better-ui)" '"off"' uninstall
  assert_eq "$(ov animate)" '' ours_removed
}

test_never_touches_foreign() {
  mk_home; mk_repo
  mkdir -p "$HOME/.claude/skills/better-ui" "$HOME/.agents/skills"
  echo mine > "$HOME/.claude/skills/better-ui/SKILL.md"
  ln -s /somewhere/else "$HOME/.claude/skills/better-colors"
  ln -s /elsewhere "$HOME/.agents/skills/other"
  run_setup
  [ -L "$HOME/.claude/skills/better-ui" ] && exit 1
  assert_eq "$(cat "$HOME/.claude/skills/better-ui/SKILL.md")" mine real_dir
  assert_eq "$(readlink "$HOME/.claude/skills/better-colors")" /somewhere/else foreign_link
  assert_eq "$(readlink "$HOME/.agents/skills/other")" /elsewhere foreign_codex
  grep -q 'better-ui' "$HOME/out" || exit 1
  grep -q 'better-colors' "$HOME/out" || exit 1
  assert_eq "$(ov better-ui)" "" no_override_for_foreign
}

test_uninstall() {
  mk_home; mk_repo
  mkdir -p "$HOME/.claude" "$KAITO_HOME/memory"
  echo '{"model":"m","skillOverrides":{"mything":"off"}}' > "$HOME/.claude/settings.json"
  echo note > "$KAITO_HOME/memory/a.md"
  run_setup
  run_setup --uninstall
  assert_no "$KAITO_HOME/store"
  assert_no "$KAITO_HOME/state.json"
  assert_no "$HOME/.claude/skills/better-ui"
  assert_no "$HOME/.agents/skills/helpmekaito"
  assert_eq "$(ov better-ui)" "" override_removed
  assert_eq "$(ov mything)" '"off"' user_entry
  assert_file "$KAITO_HOME/memory/a.md"
  assert_file "$KAITO_HOME/config.json"
  run_setup
  run_setup --purge
  assert_no "$KAITO_HOME"
  assert_no "$HOME/.claude/skills/helpmekaito"
}

test_purge_refuses_dangerous_home() {
  mk_home; mk_repo
  echo keep > "$HOME/mine.txt"; mkdir -p "$HOME/docs"; echo keep > "$HOME/docs/a.txt"
  for k in "$HOME" / relative "$HOME/docs"; do
    KAITO_HOME="$k" "$R/setup" --purge > "$HOME/out" 2>&1 && { echo "purge ran for $k"; exit 1; }
  done
  assert_file "$HOME/mine.txt"; assert_file "$HOME/docs/a.txt"
  KAITO_HOME="$HOME/a\$(id)b" "$R/setup" --yes --no-gstack --no-codegraph > "$HOME/out" 2>&1 && exit 1
  return 0
}

test_lost_state_still_uninstalls_overrides() {
  mk_home; mk_repo; run_setup
  rm "$KAITO_HOME/state.json"
  run_setup
  assert_eq "$(node "$J" get "$KAITO_HOME/state.json" managed_overrides | grep -c better-ui)" 1 reclaimed
  rm "$KAITO_HOME/state.json"
  run_setup --uninstall
  assert_eq "$(ov better-ui)" "" removed
}

test_corrupt_files_stop_setup_early() {
  mk_home; mk_repo; run_setup
  echo '{"oops"' > "$KAITO_HOME/state.json"
  "$R/setup" --yes --no-gstack --no-codegraph > "$HOME/out" 2>&1 && exit 1
  "$R/setup" --uninstall > "$HOME/out" 2>&1 && exit 1
  assert_eq "$(ov better-ui)" '"name-only"' untouched
  assert_no "$KAITO_HOME/.setup.lock"
}

test_second_setup_refused_while_locked() {
  mk_home; mk_repo; run_setup
  mkdir "$KAITO_HOME/.setup.lock"
  "$R/setup" --yes --no-gstack --no-codegraph > "$HOME/out" 2>&1 && exit 1
  grep -q 'another setup' "$HOME/out" || exit 1
}

test_store_keeps_foreign_dirs_and_ships_licenses() {
  mk_home; mk_repo; run_setup
  mkdir "$KAITO_HOME/store/myskill"; echo mine > "$KAITO_HOME/store/myskill/SKILL.md"
  run_setup
  assert_file "$KAITO_HOME/store/myskill/SKILL.md"
  assert_file "$KAITO_HOME/store/THIRD_PARTY_LICENSES.md"; assert_file "$KAITO_HOME/store/LICENSE"
}
