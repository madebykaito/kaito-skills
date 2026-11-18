#!/bin/sh
. "$(dirname "$0")/lib.sh"
SY="$REPO/helpmekaito/scripts/kaito-sync.mjs"

test_mirror_excludes_includes_and_prunes() {
  mk_home; s="$HOME/src" d="$HOME/dst"
  mkdir -p "$s/a" "$s/node_modules" "$s/lib/r/dist" "$s/b/dist"
  echo 1 > "$s/a/f"; echo x > "$s/node_modules/m"; echo keep > "$s/lib/r/dist/bundle"; echo no > "$s/b/dist/out"
  node "$SY" mirror -x node_modules -i /lib/r/dist -x dist "$s" "$d"
  assert_eq "$(cat "$d/a/f")" 1 copied
  assert_no "$d/node_modules"; assert_no "$d/b/dist"
  assert_eq "$(cat "$d/lib/r/dist/bundle")" keep included
  # DEST-only files go, excluded ones stay, also inside a folder the source does not have.
  mkdir -p "$d/old" "$d/built/dist" "$d/node_modules"; echo z > "$d/old/z"; echo k > "$d/built/dist/k"; echo m > "$d/node_modules/m"
  echo 2 > "$s/a/f"
  node "$SY" mirror -x node_modules -i /lib/r/dist -x dist "$s" "$d"
  assert_eq "$(cat "$d/a/f")" 2 updated
  assert_no "$d/old"
  assert_file "$d/built/dist/k"; assert_file "$d/node_modules/m"
}

test_into_and_link() {
  mk_home
  mkdir -p "$HOME/r/one" "$HOME/r/two"; echo 1 > "$HOME/r/one/SKILL.md"; echo 2 > "$HOME/r/two/SKILL.md"
  node "$SY" into -x .git "$HOME/store" "$HOME/r/one" "$HOME/r/two/"
  assert_eq "$(cat "$HOME/store/one/SKILL.md")$(cat "$HOME/store/two/SKILL.md")" 12 into
  node "$SY" link "$HOME/store/one" "$HOME/l"
  [ -L "$HOME/l" ] || { echo "  not a link"; exit 1; }
  assert_eq "$(cat "$HOME/l/SKILL.md")" 1 through_link
  rm "$HOME/l"; assert_file "$HOME/store/one/SKILL.md"
}
