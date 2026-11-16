#!/bin/sh
. "$(dirname "$0")/lib.sh"
KP="$REPO/helpmekaito/scripts/kaito-path.sh"

# skill <dir> [frontmatter line]: writes <dir>/SKILL.md
skill() { mkdir -p "$1"; printf -- '---\nname: %s\n%s\n---\nbody\n' "$(basename "$1")" "${2:-}" > "$1/SKILL.md"; }
# kp <args>: sets out, err, rc
kp() { out=$(sh "$KP" "$@" 2> "$HOME/err"); rc=$?; err=$(cat "$HOME/err"); }

test_path_store_skill() {
  mk_home; S="$KAITO_HOME/store"; skill "$S/better-ui"
  kp better-ui; assert_eq "$rc" 0 rc; assert_eq "$out" "$S/better-ui/SKILL.md" path
  kp nope; assert_eq "$rc" 1 missing
  kp ../x; assert_eq "$rc" 1 traversal
}

test_path_gstack_skill() {
  mk_home; S="$KAITO_HOME/store"
  skill "$S/gstack"; skill "$S/_gstack-claude"; skill "$S/_gstack-claude/qa"
  skill "$S/_gstack-codex/.agents/skills/gstack-qa"; skill "$S/_gstack-codex/.agents/skills/gstack"
  kp qa; assert_eq "$out" "$S/_gstack-claude/qa/SKILL.md" claude
  kp gstack-qa; assert_eq "$out" "$S/_gstack-claude/qa/SKILL.md" prefixed
  kp gstack; assert_eq "$out" "$S/_gstack-claude/SKILL.md" router
  kp qa --host codex; assert_eq "$out" "$S/_gstack-codex/.agents/skills/gstack-qa/SKILL.md" codex
  kp gstack --host codex; assert_eq "$out" "$S/_gstack-codex/.agents/skills/gstack/SKILL.md" codex-router
}

# Renders keep only name and description (as gstack's Codex render does), so
# the flags live only in the source copy at $S/gstack/<n>.
test_path_user_only_exit3() {
  mk_home; S="$KAITO_HOME/store"
  skill "$S/gstack/land-and-deploy" 'disable-model-invocation: true'
  skill "$S/_gstack-claude/land-and-deploy"; skill "$S/_gstack-codex/.agents/skills/gstack-land-and-deploy"
  kp land-and-deploy; assert_eq "$rc" 3 rc; assert_eq "$err" user-only err
  assert_eq "$out" "$S/_gstack-claude/land-and-deploy/SKILL.md" path
  kp land-and-deploy --host codex; assert_eq "$rc" 3 codex-rc; assert_eq "$err" user-only codex-err
  assert_eq "$out" "$S/_gstack-codex/.agents/skills/gstack-land-and-deploy/SKILL.md" codex-path
  # kaito skills carry their own flags
  skill "$S/prototype" 'disable-model-invocation: true'
  kp prototype --host codex; assert_eq "$rc" 3 kaito
}

test_path_hooks_codex_exit4() {
  mk_home; S="$KAITO_HOME/store"
  skill "$S/gstack/careful" 'hooks:'
  skill "$S/_gstack-claude/careful"; skill "$S/_gstack-codex/.agents/skills/gstack-careful"
  kp careful; assert_eq "$rc" 0 claude-ok
  kp careful --host codex; assert_eq "$rc" 4 rc; assert_eq "$err" hooks err
  assert_eq "$out" "$S/_gstack-codex/.agents/skills/gstack-careful/SKILL.md" path
  kp gstack-careful --host codex; assert_eq "$rc" 4 prefixed
  # hooks: in the body is not frontmatter
  mkdir -p "$S/body"; printf -- '---\nname: body\n---\nhooks:\n' > "$S/body/SKILL.md"
  kp body --host codex; assert_eq "$rc" 0 body-only
}

test_check_routes_accepts_gstack_names() {
  mk_home; R="$HOME/kaito-skills"; H="$R/helpmekaito"
  mkdir -p "$H/scripts" "$H/references/domains"; cp "$REPO/helpmekaito/scripts/check-routes.sh" "$H/scripts/"
  skill "$H"; skill "$R/gstack"; skill "$R/gstack/qa"
  skill "$R/gstack/careful" 'hooks:'; skill "$R/gstack/land-and-deploy" 'disable-model-invocation: true'
  printf '| `gstack` | r |\n| `qa` | q |\n| `careful` | c |\n| `land-and-deploy` | l |\n' > "$H/references/domains/eng.md"
  o=$(sh "$H/scripts/check-routes.sh") || { echo "$o"; exit 1; }
  echo "$o" | grep -qx 'routes ok' || { echo "$o"; exit 1; }
  echo "$o" | grep -qx 'user-only: land-and-deploy' || { echo "$o"; exit 1; }
  echo "$o" | grep -qx 'hooks: careful' || { echo "$o"; exit 1; }
  echo '| `ghost` | g |' >> "$H/references/domains/eng.md"
  o=$(sh "$H/scripts/check-routes.sh") && { echo "should fail: $o"; exit 1; }
  echo "$o" | grep -qx 'mapped but missing: ghost' || { echo "$o"; exit 1; }
}

test_real_catalog_routes_ok() {
  out=$(sh "$REPO/helpmekaito/scripts/check-routes.sh") || { echo "$out"; exit 1; }
  case "$out" in *"routes ok"*) ;; *) echo "$out"; exit 1 ;; esac
  echo "$out" | grep -q '^user-only:.*review-animations' || { echo "$out"; exit 1; }
}
