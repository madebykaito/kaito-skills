#!/bin/sh
. "$(dirname "$0")/lib.sh"
LAYOUT="$REPO/tools/check-layout.mjs"

test_real_layout() {
  out=$(node "$LAYOUT") || exit 1
  assert_eq "$out" "layout ok" layout
}

test_split_family_fails() {
  mk_home
  mkdir -p "$HOME/demo-one" "$HOME/demo-two"
  touch "$HOME/demo-one/SKILL.md" "$HOME/demo-two/SKILL.md"
  if out=$(node "$LAYOUT" "$HOME" 2>&1); then
    echo "accepted split family"; exit 1
  fi
  echo "$out" | grep -q 'split family demo: demo-one, demo-two' || { echo "$out"; exit 1; }
}

test_bundle_and_flat_skill_fail() {
  mk_home
  mkdir -p "$HOME/demo/demo-one" "$HOME/demo-two"
  touch "$HOME/demo/demo-one/SKILL.md" "$HOME/demo-two/SKILL.md"
  printf '%s\n' '{"name":"demo","source":"local","license":"MIT","skills":["demo-one"]}' > "$HOME/demo/bundle.json"
  if out=$(node "$LAYOUT" "$HOME" 2>&1); then
    echo "accepted skill beside its bundle"; exit 1
  fi
  echo "$out" | grep -q 'split family demo: demo, demo-two' || { echo "$out"; exit 1; }
}

test_bundle_requires_skill_file() {
  mk_home
  mkdir -p "$HOME/demo/demo-one/SKILL.md"
  printf '%s\n' '{"name":"demo","source":"local","license":"MIT","skills":["demo-one"]}' > "$HOME/demo/bundle.json"
  if out=$(node "$LAYOUT" "$HOME" 2>&1); then
    echo "accepted directory as a skill file"; exit 1
  fi
  echo "$out" | grep -q 'missing skill "demo-one"' || { echo "$out"; exit 1; }
}
