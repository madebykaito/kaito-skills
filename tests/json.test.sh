#!/bin/sh
. "$(dirname "$0")/lib.sh"
J="$REPO/helpmekaito/scripts/kaito-json.mjs"

test_json_set_creates_and_merges() {
  mk_home
  node "$J" set "$HOME/a/b.json" a.b 1 || exit 1
  assert_eq "$(tr -d ' \n' < "$HOME/a/b.json")" '{"a":{"b":1}}' created
  echo '{"x":"keep"}' > "$HOME/c.json"
  node "$J" set "$HOME/c.json" y.z '"v"' || exit 1
  assert_eq "$(node "$J" get "$HOME/c.json" x)" '"keep"' kept
  assert_eq "$(node "$J" get "$HOME/c.json" y.z)" '"v"' added
}

test_json_get_missing_is_empty() {
  mk_home
  assert_eq "$(node "$J" get "$HOME/nope.json" a.b)" "" nofile
  echo '{"a":1}' > "$HOME/d.json"
  assert_eq "$(node "$J" get "$HOME/d.json" a.b)" "" nopath
}

test_json_del() {
  mk_home
  echo '{"a":{"b":1,"c":2}}' > "$HOME/e.json"
  node "$J" del "$HOME/e.json" a.b || exit 1
  assert_eq "$(node "$J" get "$HOME/e.json" a.b)" "" deleted
  assert_eq "$(node "$J" get "$HOME/e.json" a.c)" "2" sibling
}
