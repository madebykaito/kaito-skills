#!/bin/sh
. "$(dirname "$0")/lib.sh"
J="$REPO/helpmekaito/scripts/kaito-json.mjs"
NUDGE='For design, motion, copy, SEO, video, media, research or code-quality work, load helpmekaito first.'

mk_repo() {
  R="$(mktemp -d)/kaito-skills"
  rsync -a --exclude .git --exclude /gstack/ --exclude /.superpowers/ --exclude node_modules "$REPO/" "$R/"
}
run_setup() { "$R/setup" --yes --no-gstack --no-codegraph "$@" > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }; }
S() { echo "$HOME/.claude/settings.json"; }
allow() { node "$J" each "$(S)" permissions.allow; }

test_permissions_default_no() {
  mk_home; mk_repo; run_setup
  assert_eq "$(node "$J" get "$(S)" permissions)" "" none
  assert_eq "$(node "$J" get "$KAITO_HOME/state.json" managed_permissions)" "" none
}

test_permissions_yes_exact_rules() {
  mk_home; mk_repo; KAITO_ANSWERS=perms=y run_setup
  st=$KAITO_HOME/store
  want=$(printf '%s\n' 'Read(~/.kaito/**)' 'Edit(~/.kaito/memory/**)' 'Write(~/.kaito/memory/**)' \
    'Bash(~/.kaito/store/gstack/bin/*)' "Bash($st/gstack/bin/*)" \
    'Bash(~/.kaito/store/gstack/browse/dist/browse *)' "Bash($st/gstack/browse/dist/browse *)" \
    'Bash(~/.kaito/store/helpmekaito/scripts/*)' "Bash($st/helpmekaito/scripts/*)" | sort)
  assert_eq "$(allow | sort)" "$want" rules
  ! allow | grep -qx -e 'Bash' -e 'Bash(*)' || exit 1
  assert_eq "$(node "$J" each "$KAITO_HOME/state.json" managed_permissions | sort)" "$want" state
}

test_permissions_outside_home_absolute_only() {
  mk_home; mk_repo; KAITO_HOME="$(mktemp -d)/k" KAITO_ANSWERS=perms=y run_setup
  ! allow | grep -q '~' || exit 1
  assert_eq "$(allow | wc -l | tr -d ' ')" 3 abs_only
}

test_permissions_idempotent_and_uninstall_keeps_others() {
  mk_home; mk_repo
  mkdir -p "$HOME/.claude"
  echo '{"permissions":{"allow":["Bash(git status)","Read(~/.kaito/**)"]},"model":"m"}' > "$(S)"
  KAITO_ANSWERS=perms=y run_setup; KAITO_ANSWERS=perms=y run_setup
  assert_eq "$(allow | grep -cxF 'Read(~/.kaito/**)')" 1 nodup
  assert_eq "$(allow | wc -l | tr -d ' ')" 10 total
  run_setup --uninstall
  assert_eq "$(allow | sort)" 'Bash(git status)
Read(~/.kaito/**)' left
  assert_eq "$(node "$J" get "$(S)" model)" '"m"' model
}

test_nudge_block_roundtrip() {
  mk_home; mk_repo
  mkdir -p "$HOME/.claude"; printf '# mine\nkeep' > "$HOME/.claude/CLAUDE.md"
  cp "$HOME/.claude/CLAUDE.md" "$HOME/orig"
  KAITO_ANSWERS=nudge=y run_setup; KAITO_ANSWERS=nudge=y run_setup
  for f in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"; do
    assert_eq "$(grep -cxF '<!-- kaito:begin -->' "$f")" 1 begin
    grep -qxF "$NUDGE" "$f" || exit 1
  done
  run_setup --uninstall
  printf '\n' >> "$HOME/orig"
  cmp "$HOME/.claude/CLAUDE.md" "$HOME/orig" || { cat "$HOME/.claude/CLAUDE.md"; exit 1; }
  ! grep -q kaito "$HOME/.codex/AGENTS.md" || exit 1
}

test_nudge_default_no() {
  mk_home; mk_repo; run_setup
  assert_no "$HOME/.claude/CLAUDE.md"; assert_no "$HOME/.codex/AGENTS.md"
}

fake_ponytail() { mkdir -p "$R/ponytail"; printf -- '---\nname: ponytail\n---\n' > "$R/ponytail/SKILL.md"; }
ss() { node "$J" get "$(S)" hooks.SessionStart; }

test_ponytail_only_when_present() {
  mk_home; mk_repo; KAITO_ANSWERS=ponytail=y run_setup
  assert_eq "$(ss)" "" none
}

test_ponytail_hook_roundtrip() {
  mk_home; mk_repo; fake_ponytail
  mkdir -p "$HOME/.claude"
  echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo hi"}]}],"Stop":[]}}' > "$(S)"
  run_setup; assert_eq "$(ss | grep -c ponytail)" 0 default_no
  KAITO_ANSWERS=ponytail=y run_setup; KAITO_ANSWERS=ponytail=y run_setup
  want="{\"hooks\":[{\"type\":\"command\",\"command\":\"cat \\\"$KAITO_HOME/store/ponytail/SKILL.md\\\"\"}]}"
  assert_eq "$(ss)" "[{\"hooks\":[{\"type\":\"command\",\"command\":\"echo hi\"}]},$want]" entries
  run_setup --uninstall
  assert_eq "$(ss)" '[{"hooks":[{"type":"command","command":"echo hi"}]}]' left
  assert_eq "$(node "$J" get "$(S)" hooks.Stop)" '[]' stop
}

CT() { echo "$HOME/.codex/config.toml"; }

test_codexwrite_roundtrip() {
  mk_home; mk_repo
  mkdir -p "$HOME/.codex"; printf 'model = "x"\n' > "$(CT)"
  run_setup; assert_eq "$(cat "$(CT)")" 'model = "x"' default_no
  KAITO_ANSWERS=codexwrite=y run_setup; KAITO_ANSWERS=codexwrite=y run_setup
  assert_eq "$(grep -c 'kaito:begin' "$(CT)")" 1 once
  grep -qxF "writable_roots = [\"$KAITO_HOME\"]" "$(CT)" || { cat "$(CT)"; exit 1; }
  grep -qxF '[sandbox_workspace_write]' "$(CT)" || exit 1
  run_setup --uninstall
  assert_eq "$(cat "$(CT)")" 'model = "x"' left
}

test_codexwrite_honors_codex_home() {
  mk_home; mk_repo; CODEX_HOME="$HOME/ch" KAITO_ANSWERS=codexwrite=y run_setup
  grep -q writable_roots "$HOME/ch/config.toml" || exit 1
  assert_no "$HOME/.codex/config.toml"
}

test_codexwrite_existing_roots_left_alone() {
  mk_home; mk_repo
  mkdir -p "$HOME/.codex"; printf '[sandbox_workspace_write]\nwritable_roots = ["/x"]\n' > "$(CT)"
  cp "$(CT)" "$HOME/orig"
  KAITO_ANSWERS=codexwrite=y run_setup
  cmp "$(CT)" "$HOME/orig" || exit 1
  grep -q writable_roots "$HOME/out" || exit 1
  run_setup --uninstall
  cmp "$(CT)" "$HOME/orig" || exit 1
}
