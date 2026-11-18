#!/bin/sh
. "$(dirname "$0")/lib.sh"
J="$REPO/helpmekaito/scripts/kaito-json.mjs"

# Temp repo with a tiny fake gstack/ (the real one is built by hand, see the task report).
mk_repo() {
  R="$(mktemp -d)/kaito-skills"
  node "$REPO/helpmekaito/scripts/kaito-sync.mjs" mirror -x .git -x /gstack -x /.superpowers -x node_modules "$REPO" "$R"
  mkdir -p "$R/gstack/node_modules"
  echo 'name: gstack' > "$R/gstack/SKILL.md"
  printf 'node_modules/\ndist/\n!lib/diagram-render/dist/\n' > "$R/gstack/.gitignore"
  touch "$R/gstack/node_modules/from-repo"
  mkdir -p "$R/gstack/lib/diagram-render/dist" && touch "$R/gstack/lib/diagram-render/dist/bundle.html"
  git -C "$R" init -q && git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -qm init
}
run_setup() {
  "$R/setup" --yes --no-codegraph "$@" > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }
}
ov() { node "$J" get "$HOME/.claude/settings.json" "skillOverrides.$1"; }
S() { echo "$KAITO_HOME/store"; }

# BUN_STUB_PROBE_FAIL=1: the stub's Chromium probe fails, so setup must install Chromium.
test_gstack_stage_order() {
  mk_home; mk_repo
  BUN_STUB_PROBE_FAIL=1 run_setup
  st=$(S)
  want="bun install
bun run build
bun x playwright install chromium
bun run gen:skill-docs:user --host claude --install-root $st/gstack --out-dir $st/_gstack-claude --link-root $st/_gstack-claude
bun run gen:skill-docs:user --host codex --install-root $st/gstack --out-dir $st/_gstack-codex --link-root $st/_gstack-codex"
  assert_eq "$(grep -v -- --eval "$HOME/stub.log")" "$want" order
  grep -q -- --eval "$HOME/stub.log" || { echo "  no chromium probe"; exit 1; }
  rm "$HOME/stub.log"; run_setup
  grep -q 'playwright install' "$HOME/stub.log" && { echo "  installed chromium though it launches"; exit 1; }
  return 0
}

test_gstack_links() {
  mk_home; mk_repo
  mkdir -p "$HOME/.claude/skills/ship"; echo mine > "$HOME/.claude/skills/ship/SKILL.md"
  mkdir -p "$KAITO_HOME"; echo '{"hot":["qa"]}' > "$KAITO_HOME/config.json"
  BUN_STUB_SKILLS="qa ship better-ui review" run_setup
  assert_eq "$(readlink "$HOME/.claude/skills/gstack")" "$(S)/_gstack-claude" router
  assert_no "$HOME/.claude/skills/bin"
  assert_eq "$(cat "$(S)/_gstack-claude/qa-ref.md")" "run $(S)/gstack/bin/x" home_path_rewritten
  assert_link "$HOME/.claude/skills/review" "$(S)/_gstack-claude/review"
  assert_link "$HOME/.claude/skills/qa" "$(S)/_gstack-claude/qa"
  assert_link "$HOME/.claude/skills/better-ui" "$(S)/better-ui"
  # The Codex render and the loader must agree on the layout.
  assert_eq "$(sh "$REPO/helpmekaito/scripts/kaito-path.sh" review --host codex)" "$(S)/_gstack-codex/.agents/skills/gstack-review/SKILL.md" codex_loader
  assert_eq "$(ov gstack)" '"name-only"' router_override
  assert_eq "$(ov review)" '"name-only"' sub_override
  assert_eq "$(ov qa)" "" hot_visible
  assert_eq "$(ov ship)" "" foreign_no_override
  assert_eq "$(cat "$HOME/.claude/skills/ship/SKILL.md")" mine foreign_kept
  grep -q 'skip.*ship' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  grep -q 'warning.*better-ui' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  assert_eq "$(ls "$HOME/.agents/skills")" helpmekaito no_codex_gstack
  before=$(ls -l "$HOME/.claude/skills")
  BUN_STUB_SKILLS="qa ship better-ui review" run_setup
  assert_eq "$(ls -l "$HOME/.claude/skills")" "$before" idempotent
}

test_no_gstack_flag() {
  mk_home; mk_repo
  run_setup --no-gstack
  assert_no "$(S)/gstack"; assert_no "$(S)/_gstack-claude"; assert_no "$(S)/_gstack-codex"
  assert_no "$HOME/.claude/skills/gstack"
  assert_no "$HOME/stub.log"
}

test_gstack_off_cleans_up() {
  mk_home; mk_repo
  run_setup
  assert_link "$HOME/.claude/skills/qa" "$(S)/_gstack-claude/qa"
  node "$J" set "$KAITO_HOME/config.json" gstack false
  rm "$HOME/stub.log"
  run_setup  # the stub.log check below proves bun is never called
  assert_no "$HOME/.claude/skills/gstack"; assert_no "$HOME/.claude/skills/qa"
  assert_eq "$(ov gstack)" "" override_dropped
  assert_link "$HOME/.claude/skills/better-ui" "$(S)/better-ui"
  assert_no "$HOME/stub.log"
}

test_foreign_gstack_untouched() {
  mk_home; mk_repo
  mkdir -p "$HOME/.claude/skills/gstack"; echo theirs > "$HOME/.claude/skills/gstack/SKILL.md"
  run_setup
  assert_eq "$(cat "$HOME/.claude/skills/gstack/SKILL.md")" theirs kept
  assert_no "$HOME/.claude/skills/qa"; assert_no "$HOME/.claude/skills/ship"
  assert_eq "$(ov qa)" "" no_override
  grep -q 'warning.*\.claude/skills/gstack' "$HOME/out" || { cat "$HOME/out"; exit 1; }
}

test_gstack_copy_excludes_build() {
  mk_home; mk_repo
  run_setup
  assert_no "$(S)/gstack/node_modules/from-repo"
  assert_file "$(S)/gstack/node_modules/.stub"
  assert_file "$(S)/gstack/browse/dist/browse"
  assert_file "$(S)/gstack/lib/diagram-render/dist/bundle.html"
  assert_no "$R/gstack/.agents"; assert_no "$R/gstack/browse"
  assert_eq "$(git -C "$R" status --porcelain)" "" repo_clean
  rm "$(S)/gstack/node_modules/.stub"; touch "$(S)/gstack/browse/dist/kept"
  BUN_STUB_SKILLS="ship" run_setup
  assert_file "$(S)/gstack/browse/dist/kept"
  assert_no "$(S)/_gstack-claude/qa"   # render is fresh each run
  assert_no "$HOME/.claude/skills/qa"
}
