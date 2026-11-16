#!/bin/sh
. "$(dirname "$0")/lib.sh"
MEM="$REPO/helpmekaito/scripts/kaito-mem.sh"
CG="$REPO/helpmekaito/scripts/kaito-codegraph.sh"

proj() { P="$(mktemp -d)/$1"; mkdir -p "$P"; P=$(cd "$P" && pwd -P); }

test_where_in_git() {
  mk_home; proj app; git -C "$P" init -q; mkdir -p "$P/sub"; mkdir "$P/.codegraph"
  out=$(cd "$P/sub" && sh "$MEM" where)
  s=$(sh "$CG" slug "$P")
  echo "$out" | grep -qx "slug=$s" || { echo "$out"; exit 1; }
  echo "$out" | grep -qx "project_file=$KAITO_HOME/memory/projects/$s.md" || exit 1
  echo "$out" | grep -qx 'indexed=yes' || exit 1
  assert_no "$KAITO_HOME/memory"
}

test_where_outside_git() {
  mk_home; proj plain
  out=$(cd "$P" && sh "$MEM" where)
  echo "$out" | grep -qx "slug=$(sh "$CG" slug "$P")" || exit 1
  echo "$out" | grep -qx 'indexed=n/a' || exit 1
  mkdir -p "$KAITO_HOME/memory"; echo "- index line" > "$KAITO_HOME/memory/MEMORY.md"
  echo "- global fact" > "$KAITO_HOME/memory/global.md"
  (cd "$P" && sh "$MEM" where) | grep -qx -- '- index line' || exit 1
  (cd "$P" && sh "$MEM" where) | grep -qx -- '- global fact' || exit 1
  for i in $(seq 1 60); do echo "- l$i" >> "$KAITO_HOME/memory/MEMORY.md"; done
  out=$(cd "$P" && sh "$MEM" where)
  assert_eq "$(echo "$out" | wc -l | tr -d ' ')" 40 lines
  assert_eq "$(echo "$out" | tail -1)" "..." tail
}

test_no_index_offer_for_home() {
  mk_home
  (cd "$HOME" && sh "$MEM" where) | grep -qx 'indexed=n/a' || exit 1
  (cd / && sh "$MEM" where) | grep -qx 'indexed=n/a' || exit 1
}

test_note_project_creates_index_line_once() {
  mk_home; proj app; s=$(sh "$CG" slug "$P")
  (cd "$P" && sh "$MEM" note project "uses pnpm") 
  (cd "$P" && sh "$MEM" note project "tests: pnpm test")
  f="$KAITO_HOME/memory/projects/$s.md"
  assert_eq "$(grep -c "^- $(date +%Y-%m-%d) " "$f")" 2 notes
  assert_eq "$(grep -c "projects/$s.md" "$KAITO_HOME/memory/MEMORY.md")" 1 index
  sh "$MEM" note global "prefers short answers"
  grep -q 'prefers short answers' "$KAITO_HOME/memory/global.md" || exit 1
}

test_note_rejects_secret() {
  mk_home; proj app
  for t in "API_KEY=abc" "my token: x" "Password = hunter2" "api-key:z"; do
    (cd "$P" && sh "$MEM" note project "$t" 2>/dev/null); rc=$?
    assert_eq "$rc" 2 "$t"
  done
  assert_no "$KAITO_HOME/memory"
}

test_codegraph_decision() {
  mk_home; proj app; s=$(sh "$CG" slug "$P")
  (cd "$P" && sh "$MEM" codegraph-decision no && sh "$MEM" codegraph-decision yes)
  assert_eq "$(grep -c '^codegraph:' "$KAITO_HOME/memory/projects/$s.md")" 1 once
  grep -qx 'codegraph: yes' "$KAITO_HOME/memory/projects/$s.md" || exit 1
}

test_note_read_only_fallback() {
  mk_home; proj app
  mkdir -p "$KAITO_HOME/memory"; chmod 555 "$KAITO_HOME/memory"
  out=$(cd "$P" && sh "$MEM" note global "x"); rc=$?
  chmod 755 "$KAITO_HOME/memory"
  assert_eq "$rc" 0 rc
  assert_eq "$out" "memory is read-only here; to allow Codex writes run setup and answer yes to codexwrite" msg
}

test_mirror_called() {
  mk_home; proj app
  d=$(mktemp -d); mkdir -p "$d"; cp "$MEM" "$d/"; cp "$CG" "$d/"
  printf '#!/bin/sh\necho "$@" >> "$HOME/mirror.log"\nexit 1\n' > "$d/kaito-obsidian.sh"; chmod +x "$d/kaito-obsidian.sh"
  (cd "$P" && sh "$d/kaito-mem.sh" note global "hi") || exit 1
  grep -qx 'push global.md' "$HOME/mirror.log" || { cat "$HOME/mirror.log"; exit 1; }
}

test_note_is_literal() {
  mk_home; proj app; s=$(sh "$CG" slug "$P")
  (cd "$P" && sh "$MEM" note project 'run grep "\d+" a\tb\nc\cd')
  want='run grep "\d+" a\tb\nc\cd'
  grep -qF "$want" "$KAITO_HOME/memory/projects/$s.md" || { cat "$KAITO_HOME/memory/projects/$s.md"; exit 1; }
  assert_eq "$(wc -l < "$KAITO_HOME/memory/projects/$s.md" | tr -d ' ')" 1 lines
  (cd "$P" && sh "$MEM" where) | grep -qF "$want" || exit 1
}

test_note_newline_and_secret_shapes() {
  mk_home; P="$(mktemp -d)/app"; mkdir -p "$P"; git -C "$P" init -q
  (cd "$P" && sh "$REPO/helpmekaito/scripts/kaito-mem.sh" note project "x
codegraph: yes") || exit 1
  ! grep -rq '^codegraph:' "$KAITO_HOME/memory/projects" || exit 1
  (cd "$P" && sh "$REPO/helpmekaito/scripts/kaito-mem.sh" note global "password is hunter2" 2>/dev/null) && exit 1
  assert_no "$KAITO_HOME/memory/.lock"
}
