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

test_json_empty_file() {
  mk_home
  : > "$HOME/f.json"
  node "$J" set "$HOME/f.json" a 1 || exit 1
  assert_eq "$(node "$J" get "$HOME/f.json" a)" 1 empty
}

test_json_corrupt_untouched() {
  mk_home
  printf '{"a":1,}\n' > "$HOME/g.json"
  cp "$HOME/g.json" "$HOME/g.orig"
  node "$J" set "$HOME/g.json" b 2 2>/dev/null && exit 1
  node "$J" del "$HOME/g.json" a 2>/dev/null && exit 1
  cmp "$HOME/g.json" "$HOME/g.orig" || exit 1
  echo 'null' > "$HOME/h.json"
  node "$J" set "$HOME/h.json" b 2 2>/dev/null && exit 1
  echo '[1]' > "$HOME/i.json"
  node "$J" set "$HOME/i.json" b 2 2>/dev/null && exit 1
  assert_eq "$(cat "$HOME/i.json")" '[1]' array
  assert_eq "$(node "$J" get "$HOME/g.json" a)" "" lenient_get
}

test_json_settings_like() {
  mk_home
  echo '{"permissions":{"allow":["x"]},"model":"m"}' > "$HOME/s.json"
  node "$J" set "$HOME/s.json" skillOverrides.foo '"off"' || exit 1
  assert_eq "$(node "$J" get "$HOME/s.json" permissions)" '{"allow":["x"]}' perms
  assert_eq "$(node "$J" get "$HOME/s.json" model)" '"m"' model
  assert_eq "$(node "$J" get "$HOME/s.json" skillOverrides.foo)" '"off"' added
}

test_json_add_rm_each() {
  mk_home
  f="$HOME/a.json"
  node "$J" add "$f" p.list '"x y"'; node "$J" add "$f" p.list '"x y"'; node "$J" add "$f" p.list '{"a":1}'
  assert_eq "$(node "$J" get "$f" p.list)" '["x y",{"a":1}]' add_once
  assert_eq "$(node "$J" each "$f" p.list)" 'x y
{"a":1}' each
  node "$J" rm "$f" p.list '"x y"'
  assert_eq "$(node "$J" get "$f" p.list)" '[{"a":1}]' rm
  assert_eq "$(node "$J" each "$f" nope)" "" each_missing
}

test_json_rm_missing_keeps_parent() {
  mk_home
  echo '{"a":1}' > "$HOME/r.json"
  node "$J" rm "$HOME/r.json" a.b '"x"' || exit 1
  assert_eq "$(tr -d ' \n' < "$HOME/r.json")" '{"a":1}' parent_kept
  node "$J" add "$HOME/r.json" a '"x"' 2>/dev/null && exit 1
  assert_eq "$(tr -d ' \n' < "$HOME/r.json")" '{"a":1}' add_refused
}

test_json_write_keeps_symlink_and_mode() {
  mk_home
  mkdir "$HOME/dots"; echo '{}' > "$HOME/dots/s.json"; chmod 600 "$HOME/dots/s.json"
  ln -s "$HOME/dots/s.json" "$HOME/s.json"
  node "$J" set "$HOME/s.json" a 1 || exit 1
  [ -L "$HOME/s.json" ] || exit 1
  assert_eq "$(node "$J" get "$HOME/dots/s.json" a)" 1 written
  [ "$IS_WIN" = 1 ] || assert_eq "$(ls -l "$HOME/dots/s.json" | cut -c1-10)" "-rw-------" mode  # Windows keeps no modes
  assert_eq "$(ls "$HOME/dots" | wc -l | tr -d ' ')" 1 no_tmp_left
}

test_json_scalar_parent_and_dangling_link() {
  mk_home
  echo '{"permissions":"keep"}' > "$HOME/p.json"
  node "$J" add "$HOME/p.json" permissions.allow '"x"' 2>/dev/null && exit 1
  assert_eq "$(tr -d ' \n' < "$HOME/p.json")" '{"permissions":"keep"}' scalar_kept
  ln -s "$HOME/later/t.json" "$HOME/d.json"
  node "$J" set "$HOME/d.json" a 1 || exit 1
  [ -L "$HOME/d.json" ] || exit 1
  assert_eq "$(node "$J" get "$HOME/later/t.json" a)" 1 through_link
  echo '{}' > "$HOME/m.json"; chmod 664 "$HOME/m.json"
  (umask 077; node "$J" set "$HOME/m.json" a 1)
  [ "$IS_WIN" = 1 ] || assert_eq "$(ls -l "$HOME/m.json" | cut -c1-10)" "-rw-rw-r--" mode_exact
}
