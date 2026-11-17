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
  for k in "$HOME" / relative "$HOME/docs" "$HOME/new/../../$(basename "$HOME")"; do
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

# A stub kaito-tasks.sh in the repo copy: records calls, "credentials: <$HOME/cred or no>".
stub_tasks() {
  cat > "$R/helpmekaito/scripts/kaito-tasks.sh" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/calls"
case "$1" in
  status) echo "credentials: $(cat "$HOME/cred" 2>/dev/null || echo no)" ;;
  boards) echo "b1 Board One" ;;
esac
exit 0
STUB
}
cfg() { node "$J" get "$KAITO_HOME/config.json" "$1"; }

test_tasks_default_yes_leaves_pending() {
  mk_home; mk_repo; stub_tasks; run_setup
  assert_eq "$(cfg tasks.state)" '"pending"' pending
  assert_eq "$(cfg tasks.manager)" "" nothing_asked
  assert_no "$HOME/calls"
}

test_tasks_none_skips() {
  mk_home; mk_repo; stub_tasks; KAITO_ANSWERS=tasks_manager=none run_setup
  assert_eq "$(cfg tasks.state)" '"skipped"' skipped
  assert_no "$HOME/calls"
}

test_tasks_obsidian_done() {
  mk_home; mk_repo; stub_tasks
  KAITO_ANSWERS="tasks_manager=obsidian,tasks_memory=$HOME/vault/mem,tasks_vault=$HOME/vault" run_setup
  assert_eq "$(cfg tasks.state)" '"done"' done
  assert_eq "$(cfg memory.path)" "\"$HOME/vault/mem\"" memory
  assert_eq "$(cfg obsidian.vault_root)" "\"$HOME/vault\"" vault
  assert_eq "$(cfg tasks.steps.discovery)" true discovery
}

test_tasks_trello_no_credentials_stays_pending() {
  mk_home; mk_repo; stub_tasks
  KAITO_ANSWERS=tasks_manager=trello run_setup
  assert_eq "$(cfg tasks.state)" '"pending"' pending
  assert_eq "$(cfg tasks.steps.manager)" true manager
  assert_eq "$(cfg tasks.steps.memory)" true memory
  assert_eq "$(cfg tasks.steps.credentials)" "" credentials_unset
  grep -q "kaito-tasks.sh login" "$HOME/out" || { cat "$HOME/out"; exit 1; }
  ! grep -qx 'login' "$HOME/calls" || exit 1  # no tty: login is never run
}

test_tasks_trello_discovery_consent() {
  mk_home; mk_repo; stub_tasks; echo yes > "$HOME/cred"
  KAITO_ANSWERS="tasks_manager=trello,tasks_boards=b1 b2" run_setup
  assert_eq "$(cfg tasks.state)" '"done"' done
  grep -qx 'consent yes b1 b2' "$HOME/calls" || { cat "$HOME/calls"; exit 1; }
  grep -qx 'discover' "$HOME/calls" || exit 1
}

test_tasks_trello_discovery_refused() {
  mk_home; mk_repo; stub_tasks; echo yes > "$HOME/cred"
  KAITO_ANSWERS="tasks_manager=trello,tasks_boards=b1,tasks_discover=n" run_setup
  assert_eq "$(cfg tasks.state)" '"done"' done
  grep -qx 'consent no b1' "$HOME/calls" || exit 1
  ! grep -qx 'discover' "$HOME/calls" || exit 1
}

test_tasks_resume_does_not_reask() {
  mk_home; mk_repo; stub_tasks
  KAITO_ANSWERS=tasks_manager=trello run_setup  # credentials missing: pending
  echo yes > "$HOME/cred"
  # manager and memory are done; a different manager answer must not be used
  KAITO_ANSWERS="tasks_manager=asana,tasks_boards=b1" run_setup
  assert_eq "$(cfg tasks.manager)" '"trello"' not_reasked
  assert_eq "$(cfg tasks.state)" '"done"' done
}

test_tasks_done_asks_only_change() {
  mk_home; mk_repo; stub_tasks
  KAITO_ANSWERS=tasks_manager=obsidian run_setup
  KAITO_ANSWERS=tasks_manager=none run_setup
  assert_eq "$(cfg tasks.manager)" '"obsidian"' kept
  KAITO_ANSWERS=tasks_change=y,tasks_manager=none run_setup
  assert_eq "$(cfg tasks.state)" '"skipped"' changed
}
