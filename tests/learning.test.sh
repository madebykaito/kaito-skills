#!/bin/sh
. "$(dirname "$0")/lib.sh"
MEM="$REPO/helpmekaito/scripts/kaito-mem.sh"
CG="$REPO/helpmekaito/scripts/kaito-codegraph.sh"

proj() { P="$(mktemp -d)/$1"; mkdir -p "$P"; P=$(cd "$P" && pwd -P); s=$(sh "$CG" slug "$P"); f="$KAITO_HOME/memory/projects/$s.md"; }
mem() { (cd "$P" && sh "$MEM" "$@"); }
on() { d=$1; shift; (cd "$P" && KAITO_TODAY=$d sh "$MEM" "$@"); }  # on <date> <command...>

test_learn_stores_a_line() {
  mk_home; proj app
  on 2026-03-02 learn correction 'use pnpm, not npm (a\tb "q")' || exit 1
  assert_eq "$(cat "$f")" 'learn: correction 1 2026-03-02 use pnpm, not npm (a\tb "q")' line
  assert_eq "$(grep -c "projects/$s.md" "$KAITO_HOME/memory/MEMORY.md")" 1 index
  assert_eq "$(cat "$KAITO_HOME/memory/learning.log")" "2026-03-02 $s correction" log
  on 2026-03-02 learn preference "short answers" global || exit 1
  grep -qx 'learn: preference 1 2026-03-02 short answers' "$KAITO_HOME/memory/global.md" || exit 1
  assert_eq "$(wc -l < "$f" | tr -d ' ')" 1 "global stays out of the project file"
}

test_learn_twice_bumps_count_and_date() {
  mk_home; proj app
  mem note project "uses pnpm"
  on 2026-03-02 learn correction "Use pnpm, not npm" || exit 1
  on 2026-03-09 learn worked "  use PNPM not npm. " || exit 1
  assert_eq "$(grep -c '^learn:' "$f")" 1 "one line"
  grep -qx 'learn: correction 2 2026-03-09 Use pnpm, not npm' "$f" || { cat "$f"; exit 1; }
  grep -q 'uses pnpm' "$f" || exit 1
  assert_eq "$(wc -l < "$KAITO_HOME/memory/learning.log" | tr -d ' ')" 2 "every capture is logged"
}

test_learn_usage_and_secrets() {
  mk_home; proj app
  for a in "bogus x" "correction" "correction  " ; do
    # shellcheck disable=SC2086
    (cd "$P" && sh "$MEM" learn $a 2>/dev/null); assert_eq "$?" 2 "usage: $a"
  done
  (mem learn correction x elsewhere 2>/dev/null); assert_eq "$?" 2 scope
  (cd "$P" && KAITO_TODAY=tomorrow sh "$MEM" learn correction x 2>/dev/null); assert_eq "$?" 2 today
  for t in "the token: abc" "key sk-abcdefghijklmnop1234" "ghp_abcdefghijklmnopqrstuvwxyz0123" \
      "AKIAABCDEFGHIJKLMNOP is the id" "hash 0123456789abcdef0123456789abcdef01234567" "-----BEGIN RSA PRIVATE KEY-----"; do
    (mem learn convention "$t" 2>/dev/null); assert_eq "$?" 2 "$t"
  done
  assert_no "$KAITO_HOME/memory"
}

test_where_shows_learnings_capped_and_ordered() {
  mk_home; proj app
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do on 2026-03-01 learn convention "old fact number $i is here" || exit 1; done
  on 2026-03-05 learn correction "newest wins ties" || exit 1
  on 2026-03-02 learn preference "confirmed twice" global && on 2026-03-03 learn preference "confirmed twice" global || exit 1
  mem set board "trello b1 Main"; mem note project "plain note"
  out=$(mem where)
  assert_eq "$(echo "$out" | sed -n 4p)" "board: trello b1 Main" "board first"
  assert_eq "$(echo "$out" | sed -n 5p)" "learn: preference 2 2026-03-03 confirmed twice" "most confirmed first"
  assert_eq "$(echo "$out" | sed -n 6p)" "learn: correction 1 2026-03-05 newest wins ties" "then most recent"
  assert_eq "$(echo "$out" | grep -c '^learn:')" 10 cap
  echo "$out" | grep -qx 'learn_more: 4 not shown; run kaito-mem.sh curate' || { echo "$out"; exit 1; }
  echo "$out" | grep -q 'plain note' || exit 1
}

test_curate_flags_duplicate_stale_and_promotion() {
  mk_home; proj app
  assert_eq "$(on 2026-06-01 curate)" "learnings: 0
nothing to curate" empty
  on 2026-03-01 learn failed "codex runner times out on big diffs" || exit 1
  on 2026-05-20 learn convention "tests live in tests/ and run with sh tests/run.sh" || exit 1
  on 2026-05-21 learn convention "tests live in tests and run with tests/run.sh" || exit 1
  for d in 2026-05-10 2026-05-17 2026-05-24; do on $d learn correction "say the route before starting" || exit 1; done
  on 2026-05-25 learn preference "British spelling" global || exit 1
  printf '%s\n' "learn: worked 1 2026-05-30 british spelling" >> "$f"  # a hand edit: same text in two files
  before=$(cat "$f")
  out=$(on 2026-06-01 curate)
  echo "$out" | grep -qx 'learnings: 6' || { echo "$out"; exit 1; }
  echo "$out" | grep -qx 'duplicate: convention 1x 2026-05-20 tests live in tests/ and run with sh tests/run.sh || convention 1x 2026-05-21 tests live in tests and run with tests/run.sh' || { echo "$out"; exit 1; }
  echo "$out" | grep -qx 'duplicate: worked 1x 2026-05-30 british spelling || preference 1x 2026-05-25 British spelling' || { echo "$out"; exit 1; }
  assert_eq "$(echo "$out" | grep -c '^duplicate:')" 2 duplicates
  assert_eq "$(echo "$out" | grep '^stale:')" "stale: failed 1x 2026-03-01 codex runner times out on big diffs" stale
  assert_eq "$(echo "$out" | grep '^promote:')" "promote: correction 3x 2026-05-24 say the route before starting" promote
  assert_eq "$(cat "$f")" "$before" "curate changes nothing"
}

test_forget_and_promote() {
  mk_home; proj app
  mem learn correction "say the route before starting" && mem learn failed "codex runner times out" || exit 1
  mem learn preference "British spelling" global || exit 1
  mem forget "CODEX runner: times out!" || exit 1
  ! grep -q codex "$f" || exit 1
  mem promote "say the route before starting" || exit 1
  assert_eq "$(cat "$f")" "rule: say the route before starting" rule
  assert_eq "$(mem where | sed -n 4p)" "rule: say the route before starting" "rule printed first"
  mem promote "british spelling" || exit 1
  assert_eq "$(cat "$KAITO_HOME/memory/global.md")" "rule: British spelling" "global rule"
  (mem forget "never captured" 2>/dev/null); assert_eq "$?" 1 missing
  (mem forget 2>/dev/null); assert_eq "$?" 2 usage
  assert_no "$KAITO_HOME/memory/.lock"
}

test_stats_counts_corrections_by_week() {
  mk_home; proj app; a=$s
  on 2026-06-01 learn correction "one" && on 2026-06-08 learn correction "two" && on 2026-06-09 learn correction "two" || exit 1
  on 2026-06-25 learn correction "three" && on 2026-06-28 learn worked "not a correction" || exit 1
  on 2026-05-01 learn correction "too old" || exit 1
  proj other; b=$s
  on 2026-06-27 learn correction "elsewhere" global || exit 1
  out=$(on 2026-06-28 stats)
  assert_eq "$(echo "$out" | sed -n 1p)" "corrections per week, oldest first; the last week ends 2026-06-28" head
  echo "$out" | grep -qx "$a: 1 2 0 1" || { echo "$out"; exit 1; }
  echo "$out" | grep -qx "$b: 0 0 0 1" || { echo "$out"; exit 1; }
  proj third
  on 2026-06-28 stats | grep -qx "$s: 0 0 0 0" || exit 1
}

test_learnings_stay_in_their_project() {
  mk_home; proj one
  mem learn convention "only in project one" && mem learn preference "everywhere" global || exit 1
  proj two
  out=$(mem where)
  ! echo "$out" | grep -q 'only in project one' || { echo "$out"; exit 1; }
  echo "$out" | grep -q '^learn: preference 1 .* everywhere$' || { echo "$out"; exit 1; }
  assert_eq "$(mem curate | sed -n 1p)" "learnings: 1" curate
  (mem forget "only in project one" 2>/dev/null); assert_eq "$?" 1 "cannot forget another project's learning"
}
