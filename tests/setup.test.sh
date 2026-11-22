#!/bin/sh
. "$(dirname "$0")/lib.sh"
J="$REPO/helpmekaito/scripts/kaito-json.mjs"

# Copy the repo to a temp dir so setup never touches the real checkout.
mk_repo() {
  R="$(mktemp -d)/kaito-skills"
  node "$REPO/helpmekaito/scripts/kaito-sync.mjs" mirror -x .git -x .codegraph -x ./gstack -x ./.superpowers -x node_modules "$REPO" "$R"
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

test_uninstall_removes_closeout() {
  mk_home; mk_repo; mkdir -p "$KAITO_HOME/memory"; run_setup
  mkdir -p "$KAITO_HOME/closeout"; echo "2026-11-22 open" > "$KAITO_HOME/closeout/some-project"
  run_setup --uninstall
  assert_no "$KAITO_HOME/closeout"
  assert_file "$KAITO_HOME/config.json"
  assert_file "$KAITO_HOME/memory"
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
  boards) printf 'b1 Board One\nb2 Board Two\n' ;;
esac
exit 0
STUB
  export KAITO_OBSIDIAN_JSON="$HOME/obsidian.json"  # never the real Obsidian's vault list
}
# mk_vaults <dir>...: Obsidian knows these vaults.
mk_vaults() {
  for v; do mkdir -p "$v"; done
  node -e 'const o = {}; process.argv.slice(1).forEach((p, i) => { o["v" + i] = { path: p } }); console.log(JSON.stringify({ vaults: o }))' "$@" > "$KAITO_OBSIDIAN_JSON"
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
  mk_home; mk_repo; stub_tasks; mk_vaults "$HOME/vault"
  KAITO_ANSWERS="tasks_manager=obsidian,tasks_memory=$HOME/vault/mem" run_setup
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

test_tasks_obsidian_defaults_into_vault() {
  mk_home; mk_repo; stub_tasks; mk_vaults "$HOME/notes" "$HOME/work"
  KAITO_ANSWERS="tasks_manager=obsidian,tasks_vault=2" run_setup
  assert_eq "$(cfg memory.path)" "\"$HOME/work/kaito\"" memory_in_vault
  assert_eq "$(cfg obsidian.vault_root)" "\"$HOME/work\"" vault
  grep -q '2) .*work' "$HOME/out" || { cat "$HOME/out"; exit 1; }
}

test_tasks_obsidian_without_vault_stays_pending() {
  mk_home; mk_repo; stub_tasks
  KAITO_ANSWERS=tasks_manager=obsidian run_setup
  assert_eq "$(cfg tasks.state)" '"pending"' pending
  assert_eq "$(cfg tasks.steps.memory)" "" memory_unset
  grep -q 'Install Obsidian' "$HOME/out" || { cat "$HOME/out"; exit 1; }
}

test_tasks_trello_never_asks_for_a_vault() {
  mk_home; mk_repo; stub_tasks; echo yes > "$HOME/cred"; mk_vaults "$HOME/vault"
  KAITO_ANSWERS="tasks_manager=trello,tasks_memory=$HOME/vault/mem,tasks_vault=$HOME/other" run_setup
  assert_eq "$(cfg obsidian.vault_root)" "\"$HOME/vault\"" found_not_asked
  ! grep -q 'Obsidian vaults' "$HOME/out" || exit 1
}

test_tasks_trello_boards_default_all() {
  mk_home; mk_repo; stub_tasks; echo yes > "$HOME/cred"
  KAITO_ANSWERS="tasks_manager=trello" run_setup
  assert_eq "$(cfg tasks.state)" '"done"' done
  grep -q '1) Board One' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  grep -qx 'consent yes b1 b2' "$HOME/calls" || { cat "$HOME/calls"; exit 1; }
  grep -qx 'discover' "$HOME/calls" || exit 1
}

test_tasks_trello_boards_by_number_or_id() {
  mk_home; mk_repo; stub_tasks; echo yes > "$HOME/cred"
  KAITO_ANSWERS="tasks_manager=trello,tasks_boards=2 b1 9 2" run_setup
  grep -qx 'consent yes b2 b1' "$HOME/calls" || { cat "$HOME/calls"; exit 1; }
}

test_tasks_trello_boards_none() {
  mk_home; mk_repo; stub_tasks; echo yes > "$HOME/cred"
  KAITO_ANSWERS="tasks_manager=trello,tasks_boards=none" run_setup
  assert_eq "$(cfg tasks.state)" '"done"' done
  grep -qx 'consent no' "$HOME/calls" || { cat "$HOME/calls"; exit 1; }
}

test_tasks_trello_boards_no_match_stays_pending() {
  mk_home; mk_repo; stub_tasks; echo yes > "$HOME/cred"
  KAITO_ANSWERS="tasks_manager=trello,tasks_boards=7" run_setup
  assert_eq "$(cfg tasks.state)" '"pending"' pending
  ! grep -q '^consent' "$HOME/calls" || exit 1
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
  mk_vaults "$HOME/vault"
  KAITO_ANSWERS=tasks_manager=obsidian run_setup
  KAITO_ANSWERS=tasks_manager=none run_setup
  assert_eq "$(cfg tasks.manager)" '"obsidian"' kept
  KAITO_ANSWERS=tasks_change=y,tasks_manager=none run_setup
  assert_eq "$(cfg tasks.state)" '"skipped"' changed
}

test_tasks_plane_picks_projects_by_name() {
  mk_home; mk_repo; stub_tasks; echo yes > "$HOME/cred"
  KAITO_ANSWERS="tasks_manager=plane" run_setup
  assert_eq "$(cfg tasks.manager)" '"plane"' manager
  assert_eq "$(cfg tasks.state)" '"done"' done
  grep -q 'Your Plane projects:' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  grep -qx 'consent yes b1 b2' "$HOME/calls" || { cat "$HOME/calls"; exit 1; }
  grep -qx 'discover' "$HOME/calls" || exit 1
}

test_tasks_plane_no_credentials_names_login_and_mcp() {
  mk_home; mk_repo; stub_tasks
  KAITO_ANSWERS=tasks_manager=plane run_setup
  assert_eq "$(cfg tasks.state)" '"pending"' pending
  grep -q "Plane credentials are not set" "$HOME/out" || { cat "$HOME/out"; exit 1; }
  grep -q "Plane connector (MCP)" "$HOME/out" || { cat "$HOME/out"; exit 1; }
  ! grep -qx 'login' "$HOME/calls" || exit 1
}

test_tasks_linear_no_credentials_names_login_and_mcp() {
  mk_home; mk_repo; stub_tasks
  KAITO_ANSWERS=tasks_manager=linear run_setup
  assert_eq "$(cfg tasks.state)" '"pending"' pending
  grep -q "Linear credentials are not set" "$HOME/out" || { cat "$HOME/out"; exit 1; }
  grep -q "Linear connector (MCP)" "$HOME/out" || { cat "$HOME/out"; exit 1; }
  ! grep -qx 'login' "$HOME/calls" || exit 1
}

test_state_records_version_and_repo() {
  mk_home; mk_repo; run_setup
  assert_eq "$(node "$J" get "$KAITO_HOME/state.json" version)" "\"$(cat "$REPO/VERSION")\"" version
  assert_eq "$(node "$J" get "$KAITO_HOME/state.json" repo)" "\"$(cd "$R" && pwd -P)\"" repo
  assert_file "$KAITO_HOME/store/setup"; assert_file "$KAITO_HOME/store/VERSION"; assert_file "$KAITO_HOME/store/CHANGELOG.md"
  grep -q '^updates: auto ' "$HOME/out" || { cat "$HOME/out"; exit 1; }
}

# --upgrade answers nothing: a yes in KAITO_ANSWERS turns nothing on, and what an earlier run turned on stays.
test_upgrade_flag_changes_no_consent() {
  mk_home; mk_repo
  KAITO_ANSWERS="nudge=y" run_setup
  grep -q 'kaito:begin' "$HOME/.claude/CLAUDE.md" || exit 1
  KAITO_ANSWERS="perms=y,ponytail=y,nudge=y" "$R/setup" --upgrade --no-gstack --no-codegraph > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }
  grep -q 'kaito:begin' "$HOME/.claude/CLAUDE.md" || exit 1
  assert_eq "$(node "$J" get "$HOME/.claude/settings.json" permissions.allow)" "" perms_not_added
  assert_eq "$(node "$J" get "$HOME/.claude/settings.json" hooks.SessionStart)" "" hook_not_added
  assert_link "$HOME/.claude/skills/better-ui" "$KAITO_HOME/store/"
}

# The clone is gone: a copy of the store's setup, pointed at the store, still uninstalls.
test_store_setup_uninstalls_without_clone() {
  mk_home; mk_repo; run_setup
  rm -rf "$R"
  cp "$KAITO_HOME/store/setup" "$HOME/setup-copy"
  KAITO_SETUP_REPO="$KAITO_HOME/store" sh "$HOME/setup-copy" --uninstall > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }
  assert_no "$HOME/.claude/skills/better-ui"; assert_no "$KAITO_HOME/store"
  assert_eq "$(ov better-ui)" "" override_dropped
  assert_file "$KAITO_HOME/config.json"
}

test_store_setup_refuses_to_install() {
  mk_home; mk_repo; run_setup
  cp "$KAITO_HOME/store/setup" "$HOME/setup-copy"
  if KAITO_SETUP_REPO="$KAITO_HOME/store" sh "$HOME/setup-copy" --yes > "$HOME/out" 2>&1; then exit 1; fi
  grep -q 'only uninstalls' "$HOME/out" || { cat "$HOME/out"; exit 1; }
}

# --- duplicates: same-name skills and plugins the user already has
st() { node "$J" get "$KAITO_HOME/state.json" "$1"; }
mk_dup() { mkdir -p "$HOME/.claude/skills/better-ui"; echo mine > "$HOME/.claude/skills/better-ui/SKILL.md"; }
# mk_plugin <id> [enabledPlugins value]: an installed plugin with better-ui and one skill of its own.
mk_plugin() {
  pd="$HOME/.claude/plugins/cache/${1%%@*}"
  mkdir -p "$pd/skills/better-ui" "$pd/skills/own"
  echo x > "$pd/skills/better-ui/SKILL.md"; echo x > "$pd/skills/own/SKILL.md"
  node -e 'const [f, id, p] = process.argv.slice(1); require("fs").writeFileSync(f, JSON.stringify({ version: 2, plugins: { [id]: [{ scope: "user", installPath: p }] } }))' \
    "$HOME/.claude/plugins/installed_plugins.json" "$1" "$pd"
  [ $# -lt 2 ] || echo "{\"enabledPlugins\":{\"$1\":$2}}" > "$HOME/.claude/settings.json"
}
# ep <id>: the plugin's value in the user settings. Not kaito-json: an id can contain dots.
ep() { node -e 'const v = (JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).enabledPlugins || {})[process.argv[2]]; console.log(v === undefined ? "" : JSON.stringify(v))' "$HOME/.claude/settings.json" "$1"; }

test_takeover_yes_moves_links_and_uninstall_restores() {
  mk_home; mk_repo; mk_dup
  KAITO_ANSWERS=takeover_skills=y run_setup
  grep -q '^duplicates: 1 skills you already have, 0 plugins' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  ! grep -q '^skip' "$HOME/out" || exit 1
  assert_eq "$(cat "$KAITO_HOME/backup/.claude/skills/better-ui/SKILL.md")" mine backup
  assert_link "$HOME/.claude/skills/better-ui" "$KAITO_HOME/store/"
  assert_eq "$(ov better-ui)" '"name-only"' override
  st taken_over | grep -qF "$HOME/.claude/skills/better-ui" || exit 1
  st links | grep -qF "$HOME/.claude/skills/better-ui" || exit 1
  run_setup  # a re-run keeps the record and asks nothing
  ! grep -q '^duplicates' "$HOME/out" || exit 1
  st taken_over | grep -qF "$HOME/.claude/skills/better-ui" || exit 1
  run_setup --uninstall
  grep -q 'restored 1 skills and 0 plugins' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  [ ! -L "$HOME/.claude/skills/better-ui" ] || exit 1
  assert_eq "$(cat "$HOME/.claude/skills/better-ui/SKILL.md")" mine restored
  assert_no "$KAITO_HOME/backup"; assert_no "$KAITO_HOME/state.json"
}

test_takeover_no_is_remembered() {
  mk_home; mk_repo; mk_dup
  KAITO_ANSWERS=takeover_skills=n run_setup
  grep -q '^duplicates: 1 skills' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  grep -q '^skip (not ours): .*better-ui' "$HOME/out" || exit 1
  assert_eq "$(cat "$HOME/.claude/skills/better-ui/SKILL.md")" mine untouched
  assert_no "$KAITO_HOME/backup"
  st declined | grep -qF "$HOME/.claude/skills/better-ui" || exit 1
  KAITO_ANSWERS=takeover_skills=y run_setup  # declined: not listed, not asked, so the yes is never used
  ! grep -q '^duplicates' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  grep -q '^skip (not ours): .*better-ui' "$HOME/out" || exit 1
  assert_eq "$(cat "$HOME/.claude/skills/better-ui/SKILL.md")" mine still_untouched
}

test_takeover_yes_flag_alone_decides_nothing() {
  mk_home; mk_repo; mk_dup; mk_plugin dup@market true
  run_setup
  grep -q '^duplicates: 1 skills you already have, 1 plugins' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  grep -q 'plugin dup@market (1 of its 2 skills)' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  grep -q '^skip (not ours): .*better-ui' "$HOME/out" || exit 1
  assert_eq "$(cat "$HOME/.claude/skills/better-ui/SKILL.md")" mine untouched
  assert_eq "$(st declined)" "" nothing_declined
  assert_eq "$(st taken_over)" "" nothing_taken
  assert_eq "$(ep dup@market)" true plugin_on
}

test_takeover_upgrade_only_reports() {
  mk_home; mk_repo; run_setup
  rm "$HOME/.claude/skills/better-ui"; mk_dup; mk_plugin dup@market
  KAITO_ANSWERS="takeover_skills=y,takeover_plugins=y" "$R/setup" --upgrade --no-gstack --no-codegraph > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }
  assert_eq "$(grep -c '^duplicates' "$HOME/out")" 1 one_line
  grep -qx 'duplicates: 2 found, run ./setup to decide' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  assert_eq "$(cat "$HOME/.claude/skills/better-ui/SKILL.md")" mine untouched
  assert_eq "$(st declined)" "" nothing_declined
  assert_eq "$(ep dup@market)" "" plugin_untouched
}

test_takeover_backup_in_the_way_leaves_skill() {
  mk_home; mk_repo; mk_dup
  mkdir -p "$KAITO_HOME/backup/.claude/skills/better-ui"; echo old > "$KAITO_HOME/backup/.claude/skills/better-ui/SKILL.md"
  KAITO_ANSWERS=takeover_skills=y run_setup
  grep -q '^warning: .*already exists' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  assert_eq "$(cat "$HOME/.claude/skills/better-ui/SKILL.md")" mine untouched
  assert_eq "$(st taken_over)" "" not_recorded
  run_setup --purge  # a backup that is still there is never deleted
  grep -q 'not deleting' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  assert_eq "$(cat "$KAITO_HOME/backup/.claude/skills/better-ui/SKILL.md")" old backup_kept
}

test_plugin_disable_and_restore_true() {
  mk_home; mk_repo; mk_plugin dup@market true
  KAITO_ANSWERS=takeover_plugins=y run_setup
  grep -q '^duplicates: 0 skills you already have, 1 plugins' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  grep -q 'Project-level plugin settings inside other repos are not changed' "$HOME/out" || exit 1
  assert_eq "$(ep dup@market)" false disabled
  assert_eq "$(st disabled_plugins.dup@market)" true previous
  run_setup  # already false: not listed again
  ! grep -q '^duplicates' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  run_setup --uninstall
  grep -q 'restored 0 skills and 1 plugins' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  assert_eq "$(ep dup@market)" true restored
}

# An id with dots, and no enabledPlugins key before: the key is removed again.
test_plugin_restore_absent_key_and_dotted_id() {
  mk_home; mk_repo; mk_plugin dup.tools@my.market
  KAITO_ANSWERS=takeover_plugins=y run_setup
  assert_eq "$(ep dup.tools@my.market)" false disabled
  assert_eq "$(node "$J" get "$HOME/.claude/settings.json" enabledPlugins.dup)" "" not_split_at_the_dot
  run_setup --uninstall
  assert_eq "$(ep dup.tools@my.market)" "" key_removed
}

test_plugin_no_is_remembered_and_reenabled_is_left_alone() {
  mk_home; mk_repo; mk_plugin dup@market
  KAITO_ANSWERS=takeover_plugins=n run_setup
  assert_eq "$(ep dup@market)" "" untouched
  st declined | grep -q '"dup@market"' || exit 1
  run_setup
  ! grep -q '^duplicates' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  node "$J" del "$KAITO_HOME/state.json" declined
  KAITO_ANSWERS=takeover_plugins=y run_setup
  assert_eq "$(ep dup@market)" false disabled
  echo '{"enabledPlugins":{"dup@market":true}}' > "$HOME/.claude/settings.json"  # the user turned it back on
  run_setup --uninstall
  ! grep -q 'restored' "$HOME/out" || exit 1
  assert_eq "$(ep dup@market)" true left_alone
}

test_purge_restores_before_deleting() {
  mk_home; mk_repo; mk_dup
  KAITO_ANSWERS=takeover_skills=y run_setup
  run_setup --purge
  assert_eq "$(cat "$HOME/.claude/skills/better-ui/SKILL.md")" mine restored
  assert_no "$KAITO_HOME"
}

test_store_setup_restores_without_clone() {
  mk_home; mk_repo; mk_dup; mk_plugin dup@market true
  KAITO_ANSWERS="takeover_skills=y,takeover_plugins=y" run_setup
  rm -rf "$R"
  cp "$KAITO_HOME/store/setup" "$HOME/setup-copy"
  KAITO_SETUP_REPO="$KAITO_HOME/store" sh "$HOME/setup-copy" --uninstall > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }
  assert_eq "$(cat "$HOME/.claude/skills/better-ui/SKILL.md")" mine restored
  assert_eq "$(ep dup@market)" true plugin_restored
}

test_duplicates_flag_asks_again() {
  mk_home; mk_repo
  mkdir -p "$HOME/.claude/skills/better-ui"; echo mine > "$HOME/.claude/skills/better-ui/SKILL.md"
  KAITO_ANSWERS="takeover_skills=n" run_setup
  KAITO_ANSWERS="takeover_skills=y" run_setup
  assert_eq "$(cat "$HOME/.claude/skills/better-ui/SKILL.md")" mine still_declined
  KAITO_ANSWERS="takeover_skills=y" run_setup --duplicates
  assert_link "$HOME/.claude/skills/better-ui" "$KAITO_HOME/store/"
}

# The user already had an override for their own skill: takeover and uninstall leave it as it was.
test_takeover_keeps_the_users_override() {
  mk_home; mk_repo
  mkdir -p "$HOME/.claude/skills/better-ui"; echo mine > "$HOME/.claude/skills/better-ui/SKILL.md"
  echo '{"skillOverrides":{"better-ui":"name-only"}}' > "$HOME/.claude/settings.json"
  KAITO_ANSWERS="takeover_skills=y" run_setup
  assert_link "$HOME/.claude/skills/better-ui" "$KAITO_HOME/store/"
  "$R/setup" --uninstall > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }
  assert_eq "$(cat "$HOME/.claude/skills/better-ui/SKILL.md")" mine restored
  assert_eq "$(ov better-ui)" '"name-only"' override_kept
}

# Task onboarding is half done: an upgrade does not answer its questions.
test_upgrade_leaves_task_onboarding_alone() {
  mk_home; mk_repo; run_setup
  echo '{"tasks":{"manager":"trello","state":"pending","steps":{"manager":true,"memory":true,"credentials":true}}}' > "$KAITO_HOME/config.json"
  before=$(cat "$KAITO_HOME/config.json")
  "$R/setup" --upgrade --no-gstack --no-codegraph > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }
  assert_eq "$(cat "$KAITO_HOME/config.json")" "$before" config_untouched
}
