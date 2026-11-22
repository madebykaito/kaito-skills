#!/bin/sh
. "$(dirname "$0")/lib.sh"
MEM="$REPO/helpmekaito/scripts/kaito-mem.sh"
CG="$REPO/helpmekaito/scripts/kaito-codegraph.sh"

fixture() {
  mk_home; KAITO_TODAY=2026-03-20; export KAITO_TODAY
  base=$(mktemp -d); P="$base/first"; Q="$base/second"
  mkdir -p "$P" "$Q"; git -C "$P" init -q; git -C "$Q" init -q
  git -C "$P" remote add origin https://github.com/Owner/Repo.git
  git -C "$Q" remote add origin git@github.com:owner/repo.git
  M="$KAITO_HOME/memory"; mkdir -p "$M/projects"
  a=$(sh "$CG" slug "$P"); b=$(sh "$CG" slug "$Q")
  s=$(cd "$P" && sh "$MEM" slug); f="$M/projects/$s.md"
}
runp() { (cd "$P" && sh "$MEM" "$@"); }
runq() { (cd "$Q" && sh "$MEM" "$@"); }
contains() { grep -Fx -- "$2" "$1" >/dev/null || { echo "missing line: $2"; cat "$1"; exit 1; }; }

test_identity_urls() {
  fixture
  expected="repo-$(printf %s github.com/owner/repo | (shasum 2>/dev/null || sha1sum) | cut -c1-8)"
  for url in 'https://github.com/Owner/Repo.git' 'git@github.com:owner/repo.git' 'ssh://git@github.com:2222/OWNER/REPO.git/' 'https://user:secret123@github.com/owner/repo.git/' 'git@gh-alias:owner/repo.git'; do
    git -C "$P" remote set-url origin "$url"
    assert_eq "$(runp slug)" "$expected" "$url"
  done
  git -C "$P" remote set-url origin 'https://other.example/owner/repo.git'
  [ "$(runp slug)" != "$expected" ] || exit 1
  git -C "$P" remote set-url origin 'https://user:secret123@github.com/owner/repo.git/'
  runp note project 'safe fact' || exit 1
  runp where > "$base/where"
  for file in "$base/where" "$M/MEMORY.md" "$f"; do
    if grep -F 'secret123' "$file"; then exit 1; fi
  done
  contains "$M/MEMORY.md" "- projects/$s.md github.com/owner/repo"
}

test_path_fallbacks() {
  fixture
  for url in none "$base/local" "file://$base/local" 'C:\\local'; do
    git -C "$P" remote remove origin 2>/dev/null || :
    [ "$url" = none ] || git -C "$P" remote add origin "$url"
    assert_eq "$(runp slug)" "$a" "$url"
  done
  mkdir "$base/plain"; assert_eq "$(cd "$base/plain" && sh "$MEM" slug)" "$(sh "$CG" slug "$base/plain")" plain
}

test_clones_and_worktree_share_memory() {
  fixture
  git -C "$P" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm initial
  git -C "$P" worktree add -q "$base/worktree" -b work
  runp note project first || exit 1
  runq note project second || exit 1
  (cd "$base/worktree" && sh "$MEM" note project third) || exit 1
  assert_eq "$(cd "$base/worktree" && sh "$MEM" slug)" "$s" worktree
  for word in first second third; do runq where | grep -F "$word" >/dev/null || exit 1; done
  assert_eq "$(wc -l < "$M/MEMORY.md" | tr -d ' ')" 1 index
  contains "$M/MEMORY.md" "- projects/$s.md github.com/owner/repo"
}

test_migrate_two_paths_and_replay_bytes() {
  fixture
  printf '%s\n' 'learn: correction 2 2026-01-01 Use pnpm, please.' 'learn: worked 1 2026-01-02 C++' 'rule: keep this' '- 2026-01-01 shared note' 'codegraph: yes' 'brief_fp: first' 'local_skill: one path desc' > "$M/projects/$a.md"
  printf '%s\n' 'learn: preference 5 2026-03-01 use PNPM please' 'learn: worked 1 2026-01-03 .NET' 'rule: keep this' 'rule: another' '- 2026-01-01 shared note' 'codegraph: no' 'brief_fp: second' 'local_skill: two path desc' > "$M/projects/$b.md"
  printf '%s\r\n' '- 2026-02-01 crlf note' >> "$M/projects/$b.md"
  printf '%s' '- 2026-02-02 no newline' >> "$M/projects/$b.md"
  printf '%s\n' "- projects/$a.md $P" "- projects/$b.md $Q" > "$M/MEMORY.md"
  printf '%s\n' "2026-01-01 $a correction" "2026-03-01 $b preference" > "$M/learning.log"
  runp slug >/dev/null || exit 1; runq where >/dev/null || exit 1
  contains "$f" 'learn: correction 5 2026-03-01 Use pnpm, please.'
  contains "$f" 'learn: worked 1 2026-01-02 C++'; contains "$f" 'learn: worked 1 2026-01-03 .NET'
  for line in 'rule: keep this' 'rule: another' '- 2026-01-01 shared note' '- 2026-02-01 crlf note' '- 2026-02-02 no newline' 'codegraph: yes' 'brief_fp: first' 'local_skill: one path desc'; do contains "$f" "$line"; done
  assert_eq "$(wc -l < "$f" | tr -d ' ')" 11 merged_lines
  assert_eq "$(cat "$M/MEMORY.md")" "- projects/$s.md github.com/owner/repo" index
  contains "$M/learning.log" "2026-01-01 $s correction"; contains "$M/learning.log" "2026-03-01 $s preference"
  assert_file "$M/projects/.migrated/$a.md"; assert_file "$M/projects/.migrated/$b.md"
  cp "$f" "$base/before"; cp "$M/MEMORY.md" "$base/index"; cp "$M/learning.log" "$base/log"
  runp slug >/dev/null; runq where >/dev/null
  cmp -s "$f" "$base/before" && cmp -s "$M/MEMORY.md" "$base/index" && cmp -s "$M/learning.log" "$base/log" || exit 1
}

test_migrate_single_old_file() {
  fixture; printf '%s\n' 'rule: old' > "$M/projects/$a.md"
  runp slug >/dev/null || exit 1
  contains "$f" 'rule: old'; assert_no "$M/projects/$a.md"; assert_file "$M/projects/.migrated/$a.md"
  contains "$M/MEMORY.md" "- projects/$s.md github.com/owner/repo"
}

test_backup_collision() {
  fixture; mkdir -p "$M/projects/.migrated"; echo previous > "$M/projects/.migrated/$a.md"; echo 'rule: new' > "$M/projects/$a.md"
  runp slug >/dev/null || exit 1
  assert_eq "$(cat "$M/projects/.migrated/$a.md")" previous backup
  contains "$M/projects/.migrated/$a.md.1" 'rule: new'
}

test_replay_converges() {
  fixture; printf '%s\n' 'learn: correction 2 2026-01-01 hello' 'rule: one' > "$M/projects/$a.md"
  runp slug >/dev/null || exit 1; cp "$f" "$base/expected"
  cp "$M/projects/.migrated/$a.md" "$M/projects/$a.md"
  runp slug >/dev/null || exit 1; cmp -s "$f" "$base/expected" || { cat "$f"; exit 1; }
}

test_readonly_fallback() {
  skip_on_win 'chmod cannot make a folder read-only' && return 0
  [ "$(id -u)" != 0 ] || { echo 'skip: root ignores read-only folders'; return 0; }
  fixture; echo 'rule: old' > "$M/projects/$a.md"; echo 'rule: new' > "$f"
  chmod 555 "$M" "$M/projects"
  out=$(runp where); rc=$?
  chmod 755 "$M" "$M/projects"
  assert_eq "$rc" 0 rc
  printf '%s\n' "$out" | grep -qx 'rule: old' || exit 1
  printf '%s\n' "$out" | grep -qx 'rule: new' || exit 1
  assert_file "$M/projects/$a.md"; runp slug >/dev/null; assert_no "$M/projects/$a.md"
  contains "$f" 'rule: old'; contains "$f" 'rule: new'
}

test_tracker_same_and_append_both_orders() {
  for order in forward reverse; do
    fixture
    if [ "$order" = forward ]; then n='tracker: trello one New | role=personal | tracking=always'; o='tracker: trello one Old | role=official | tracking=ask'; other='tracker: plane two Plane'; else n='tracker: plane two Plane'; o='tracker: trello one Old | role=official | tracking=ask'; other='tracker: plane two Other'; fi
    printf '%s\n' "$n" > "$f"; printf '%s\n' "$o" "$other" > "$M/projects/$a.md"
    runp slug >/dev/null || exit 1
    case "$order" in forward) first='tracker: trello one New | role=personal | tracking=always'; second='tracker: plane two Plane | role=official | tracking=ask' ;; reverse) first='tracker: plane two Plane | role=official | tracking=ask'; second='tracker: trello one Old | role=official | tracking=ask' ;; esac
    assert_eq "$(sed -n 1p "$f")" "$first" first; assert_eq "$(sed -n 2p "$f")" "$second" second
    assert_eq "$(grep -c '^tracker:' "$f")" 2 count
  done
}

test_tracker_conflict_both_orders() {
  for order in forward reverse; do
    fixture
    if [ "$order" = forward ]; then nid=one; oid=two; else nid=two; oid=one; fi
    echo "tracker: trello $nid New" > "$f"; echo "tracker: trello $oid Old" > "$M/projects/$a.md"
    runp slug > "$base/out" 2> "$base/err" || exit 1
    assert_eq "$(cat "$base/err")" "kaito-tasks: tracker conflict for trello: kept $nid, $oid saved as a note" warning
    contains "$f" "tracker: trello $nid New | role=official | tracking=ask"
    contains "$f" "- 2026-03-20 merged tracker: tracker: trello $oid Old"
    assert_eq "$(grep -c '^tracker:' "$f")" 1 count
  done
}

test_tracker_never_and_legacy_board() {
  for setting in 'tracking: never' 'board: none'; do
    fixture; echo "$setting" > "$f"; echo 'board: trello one Old' > "$M/projects/$a.md"
    runp slug >/dev/null || exit 1
    contains "$f" 'tracking: never'; contains "$f" '- 2026-03-20 merged tracker: board: trello one Old'
    if grep -q '^tracker:' "$f"; then exit 1; fi
  done
}

test_merge_command_and_invalid_arguments() {
  fixture; echo 'rule: manual' > "$M/projects/legacy.md"
  assert_eq "$(runp merge legacy)" "merged: legacy -> $s" result
  contains "$f" 'rule: manual'; assert_file "$M/projects/.migrated/legacy.md"
  for bad in 'a/b' 'a..b' '' missing "$s"; do
    runp merge "$bad" > "$base/out" 2> "$base/err"; rc=$?
    assert_eq "$rc" 2 "invalid $bad"; [ -s "$base/err" ] || exit 1
  done
}

test_concurrent_migration() {
  fixture; echo 'rule: old' > "$M/projects/$a.md"; echo 'rule: new' > "$f"
  runp slug > "$base/one" & p1=$!; runp slug > "$base/two" & p2=$!
  wait "$p1" || exit 1; wait "$p2" || exit 1
  assert_eq "$(cat "$base/one")" "$s" one; assert_eq "$(cat "$base/two")" "$s" two
  contains "$f" 'rule: old'; contains "$f" 'rule: new'
  assert_eq "$(wc -l < "$f" | tr -d ' ')" 2 lines
  assert_eq "$(cat "$M/MEMORY.md")" "- projects/$s.md github.com/owner/repo" index
  assert_file "$M/projects/.migrated/$a.md"; assert_no "$M/projects/$a.md"
}

test_dir_does_not_migrate() {
  fixture; echo 'rule: old' > "$M/projects/$a.md"
  assert_eq "$(runp dir)" "$M" dir; assert_file "$M/projects/$a.md"; assert_no "$f"
}

test_metadata_falls_back_to_old() {
  fixture
  printf '%s\n' 'local_skill: stale path desc' 'rule: new' > "$f"
  printf '%s\n' 'brief_fp: old' 'local_skill: old path desc' 'codegraph: no' > "$M/projects/$a.md"
  runp slug >/dev/null || exit 1
  contains "$f" 'brief_fp: old'; contains "$f" 'local_skill: old path desc'; contains "$f" 'codegraph: no'
  if grep -F 'local_skill: stale path desc' "$f"; then exit 1; fi
}

test_tracker_project_setting_merge_orders() {
  fixture; echo 'tracking: ask' > "$f"; echo 'tracking: never' > "$M/projects/$a.md"
  runp slug >/dev/null || exit 1; contains "$f" 'tracking: ask'
  fixture; echo 'tracker: trello one Active' > "$f"; echo 'tracking: never' > "$M/projects/$a.md"
  runp slug >/dev/null || exit 1; contains "$f" 'tracker: trello one Active | role=official | tracking=ask'
  if grep -q '^tracking: never' "$f"; then exit 1; fi
  fixture; echo 'rule: active' > "$f"; echo 'tracking: never' > "$M/projects/$a.md"
  runp slug >/dev/null || exit 1; contains "$f" 'tracking: never'
}

test_odd_urls() {
  fixture
  # no identity from what the parser does not understand: a helper address, an IPv6 host, an option-shaped host
  for url in 'helper::private-token' 'https://[2001:db8::1]/owner/repo' '-oProxyCommand=x:owner/repo'; do
    git -C "$P" remote set-url origin "$url"
    assert_eq "$(runp slug)" "$a" "$url"
    assert_eq "$(runp label)" "$(cd "$P" && pwd -P)" "label $url"
  done
  for url in 'https://github.com/Owner/Repo.GIT' 'https://github.com/owner/repo//'; do
    git -C "$P" remote set-url origin "$url"
    assert_eq "$(runp slug)" "$s" "$url"
  done
}

test_old_file_with_tracking_never_keeps_its_tracker() {
  fixture; printf '%s\n' 'tracker: trello one Old | role=official | tracking=ask' 'tracking: never' > "$M/projects/$a.md"
  runp slug >/dev/null || exit 1
  contains "$f" 'tracker: trello one Old | role=official | tracking=ask'; contains "$f" 'tracking: never'
  if grep -q 'merged tracker' "$f"; then exit 1; fi
}

test_merge_of_the_just_migrated_file_reports_it() {
  fixture; echo 'rule: old' > "$M/projects/$a.md"
  assert_eq "$(runp merge "$a")" "merged: $a -> $s" receipt
  contains "$f" 'rule: old'; assert_file "$M/projects/.migrated/$a.md"
}
