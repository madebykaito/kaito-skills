#!/bin/sh
. "$(dirname "$0")/lib.sh"
MEM="$REPO/helpmekaito/scripts/kaito-mem.sh"
CG="$REPO/helpmekaito/scripts/kaito-codegraph.sh"
PROJECT="$REPO/helpmekaito/scripts/kaito-project.sh"

proj() {
  P="$(mktemp -d)/$1"; mkdir -p "$P" || exit 1
  P=$(cd "$P" && pwd -P) || exit 1
  s=$(sh "$CG" slug "$P") || exit 1
  M="$KAITO_HOME/memory"; f="$M/projects/$s.md"; state="$KAITO_HOME/closeout/$s"
}
mem() { (cd "$P" && sh "$MEM" "$@"); }
on() { d=$1; shift; (cd "$P" && KAITO_TODAY=$d sh "$MEM" "$@"); }
miss_line() { printf '%s\n' "closeout_missed: a task started $1 has no recorded closeout and may still be running"; }
stats_line() { printf '%s\n' "closeouts not recorded: $1 of $2 routed tasks started in the last 28 days"; }

start_task() {
  on 2026-06-27 where task >/dev/null || exit 1
  assert_eq "$(cat "$state")" '2026-06-27 open' started
}

assert_closed_and_clean_restart() {
  assert_eq "$(cat "$state")" '2026-06-27 closed' closed
  on 2026-06-28 where > "$P/plain" || exit 1
  on 2026-06-28 where task > "$P/routed" || exit 1
  cmp "$P/plain" "$P/routed" || exit 1
  assert_eq "$(cat "$state")" '2026-06-27 closed
2026-06-28 open' restarted
}

test_capture_saved_closes_task() {
  mk_home; proj app; start_task
  out=$(printf '%s\n' 'the staging deploy uses pnpm' | on 2026-06-27 capture convention 2>"$P/error") || exit 1
  assert_eq "$out" saved receipt
  assert_eq "$(cat "$P/error")" '' stderr
  assert_eq "$(cat "$f")" 'learn: convention 1 2026-06-27 the staging deploy uses pnpm' learning
  assert_closed_and_clean_restart
}

test_capture_already_present_closes_task() {
  mk_home; proj app
  on 2026-06-26 learn convention 'the staging deploy uses pnpm' || exit 1
  start_task
  out=$(printf '%s\n' 'the staging deploy uses pnpm' | on 2026-06-27 capture worked 2>"$P/error") || exit 1
  assert_eq "$out" already_present receipt
  assert_eq "$(cat "$P/error")" '' stderr
  assert_eq "$(cat "$f")" 'learn: convention 1 2026-06-26 the staging deploy uses pnpm' learning
  assert_eq "$(cat "$M/learning.log")" "2026-06-26 $s convention" log
  assert_closed_and_clean_restart
}

test_capture_read_only_closes_task() {
  skip_on_win "chmod cannot make a folder read-only" && return 0
  [ "$(id -u)" != 0 ] || { echo "skip: root ignores read-only folders"; return 0; }
  mk_home; proj app; start_task
  mkdir -p "$M/projects" && chmod 555 "$M" || exit 1
  printf '%s\n' 'cannot save this' | on 2026-06-27 capture convention >"$P/receipt" 2>"$P/error"
  rc=$?
  chmod 755 "$M" || exit 1
  assert_eq "$rc" 73 denied
  cmp /dev/null "$P/receipt" || exit 1
  assert_eq "$(cat "$P/error")" 'memory is read-only here; to allow Codex writes run setup and answer yes to codexwrite' stderr
  assert_no "$f"
  assert_closed_and_clean_restart
}

test_capture_busy_closes_task() {
  mk_home; proj app; start_task
  lock="$M/.lock"
  mkdir -p "$lock" && printf '%s\n' "$$" > "$lock/owner" || exit 1
  printf '%s\n' 'would race a live writer' | on 2026-06-27 capture convention >"$P/receipt" 2>"$P/error"
  assert_eq "$?" 74 busy
  cmp /dev/null "$P/receipt" || exit 1
  assert_eq "$(cat "$P/error")" 'kaito-mem: memory is busy; capture was not saved' stderr
  assert_eq "$(cat "$lock/owner")" "$$" owner
  assert_no "$f"
  assert_closed_and_clean_restart
}

test_capture_failed_replace_closes_task() {
  mk_home; proj app; start_task
  mem note project 'keep this original note' || exit 1
  cp "$f" "$P/original" || exit 1
  mkdir "$P/fail-bin" || exit 1
  real_mv=$(command -v mv) || exit 1
  cat > "$P/fail-bin/mv" <<'STUB'
#!/bin/sh
[ "$2" != "$KAITO_TEST_FAILED_REPLACE" ] || exit 1
exec "$KAITO_TEST_REAL_MV" "$@"
STUB
  chmod +x "$P/fail-bin/mv" || exit 1
  printf '%s\n' 'retry after a failed replace' |
    PATH="$P/fail-bin:$PATH" KAITO_TEST_REAL_MV="$real_mv" KAITO_TEST_FAILED_REPLACE="$f" \
      on 2026-06-27 capture convention >"$P/receipt" 2>"$P/error"
  assert_eq "$?" 1 failed_replace
  cmp /dev/null "$P/receipt" || exit 1
  assert_eq "$(cat "$P/error")" 'kaito-mem: could not write the memory file; capture was not saved' stderr
  cmp "$P/original" "$f" || exit 1
  assert_no "$M/.lock"
  assert_closed_and_clean_restart
}

test_closeout_nothing_to_save_closes_task() {
  mk_home; proj app; start_task
  out=$(on 2026-06-27 closeout nothing_to_save) || exit 1
  assert_eq "$out" nothing_to_save receipt
  assert_closed_and_clean_restart
}

test_closeout_skipped_closes_task() {
  mk_home; proj app; start_task
  out=$(on 2026-06-27 closeout skipped) || exit 1
  assert_eq "$out" skipped receipt
  assert_closed_and_clean_restart
}

test_next_routed_task_reports_a_miss() {
  mk_home; proj app
  mem note project 'keep the project notes visible' || exit 1
  on 2026-06-27 where > "$P/plain" || exit 1
  on 2026-06-27 where task > "$P/first" || exit 1
  cmp "$P/plain" "$P/first" || exit 1
  assert_eq "$(cat "$state")" '2026-06-27 open' first_start
  out=$(on 2026-06-28 where task) || exit 1
  assert_eq "$(printf '%s\n' "$out" | sed -n '1,3p')" "slug=$s
project_file=$f
indexed=n/a" headers
  assert_eq "$(printf '%s\n' "$out" | grep '^closeout_missed:')" "$(miss_line 2026-06-27)" warning_once
  assert_eq "$(printf '%s\n' "$out" | sed -n '4p')" "$(miss_line 2026-06-27)" fourth_line
  printf '%s\n' "$out" | sed '4d' > "$P/without-warning" || exit 1
  cmp "$P/plain" "$P/without-warning" || exit 1
  assert_eq "$(cat "$state")" '2026-06-27 missed
2026-06-28 open' second_start
  on 2026-06-28 closeout skipped >/dev/null || exit 1
  on 2026-06-29 where task > "$P/third" || exit 1
  cmp "$P/plain" "$P/third" || exit 1
  assert_eq "$(cat "$state")" '2026-06-27 missed
2026-06-28 closed
2026-06-29 open' third_start
}

test_capture_rejection_keeps_task_open_for_retry() {
  mk_home; proj app; start_task
  cp "$state" "$P/open" || exit 1
  printf '%s\n' 'token: abc' | on 2026-06-27 capture convention >/dev/null 2>&1
  assert_eq "$?" 2 secret
  cmp "$P/open" "$state" || exit 1
  printf '\n' | on 2026-06-27 capture convention >/dev/null 2>&1
  assert_eq "$?" 2 empty
  cmp "$P/open" "$state" || exit 1
  printf '%s\n' 'use pnpm' | on 2026-06-27 capture bogus >/dev/null 2>&1
  assert_eq "$?" 2 kind
  cmp "$P/open" "$state" || exit 1
  assert_no "$f"
  out=$(printf '%s\n' 'use pnpm' | on 2026-06-27 capture convention) || exit 1
  assert_eq "$out" saved retry
  assert_closed_and_clean_restart
}

test_plain_where_ignores_open_tasks_and_other_arguments() {
  mk_home; proj app
  mem note project 'keep this project note' || exit 1
  on 2026-06-27 where > "$P/plain" || exit 1
  assert_no "$KAITO_HOME/closeout"
  start_task
  cp "$state" "$P/open" || exit 1
  on 2026-06-28 where > "$P/after" || exit 1
  cmp "$P/plain" "$P/after" && cmp "$P/open" "$state" || exit 1
  on 2026-06-28 where task extra > "$P/extra" || exit 1
  cmp "$P/plain" "$P/extra" && cmp "$P/open" "$state" || exit 1
  on 2026-06-28 where foo > "$P/foo" || exit 1
  cmp "$P/plain" "$P/foo" && cmp "$P/open" "$state" || exit 1
}

test_non_routed_commands_leave_state_untouched() {
  mk_home; proj app
  for phase in before after; do
    for cmd in note learn dir changed; do
      case "$cmd" in
        note) on 2026-06-28 note project "note $phase" || exit 1 ;;
        learn) on 2026-06-28 learn convention "lesson $phase" || exit 1 ;;
        dir) assert_eq "$(on 2026-06-28 dir)" "$M" dir ;;
        changed) assert_eq "$(KAITO_TODAY=2026-06-28 sh "$PROJECT" changed "$P")" new changed ;;
      esac
      if [ "$phase" = before ]; then
        assert_no "$KAITO_HOME/closeout"
      else
        diff -r "$P/state-before" "$KAITO_HOME/closeout" || exit 1
      fi
    done
    if [ "$phase" = before ]; then
      start_task
      cp -R "$KAITO_HOME/closeout" "$P/state-before" || exit 1
    fi
  done
}

test_where_cap_preserves_miss_and_priority_order() {
  mk_home; proj app
  mem set board 'trello b1 Main' || exit 1
  { i=0; while [ "$i" -lt 40 ]; do i=$((i + 1)); printf 's%s\tp%s\td\n' "$i" "$i"; done; } > "$P/skills" || exit 1
  mem local-skills < "$P/skills" || exit 1
  for i in 1 2 3 4 5 6 7 8 9 10; do on 2026-06-25 learn convention "fact number $i stands alone" || exit 1; done
  on 2026-06-23 learn preference 'confirmed twice' global &&
    on 2026-06-24 learn preference 'confirmed twice' global &&
    on 2026-06-26 learn correction 'newest wins ties' &&
    on 2026-06-27 learn worked 'a project rule' && mem promote 'a project rule' &&
    on 2026-06-27 learn worked 'a global rule' global && mem promote 'a global rule' &&
    mem note project 'a plain note' || exit 1
  start_task
  on 2026-06-28 where > "$P/plain" || exit 1
  on 2026-06-28 where task > "$P/routed" || exit 1
  assert_eq "$(sed -n '4,6p' "$P/routed")" "$(miss_line 2026-06-27)
board: trello b1 Main
local_skill: s1 p1 d" first_lines
  assert_eq "$(grep -c '^local_skill:' "$P/routed")" 40 skills
  assert_eq "$(sed -n '45,49p' "$P/routed")" 'local_skill: s40 p40 d
rule: a project rule
rule: a global rule
learn: preference 2 2026-06-24 confirmed twice
learn: correction 1 2026-06-26 newest wins ties' priority
  assert_eq "$(grep -c '^learn:' "$P/routed")" 10 learnings
  assert_eq "$(tail -n 2 "$P/routed")" 'learn_more: 2 not shown; run kaito-mem.sh curate
...' end
  sed '4d' "$P/routed" > "$P/without-warning" || exit 1
  cmp "$P/plain" "$P/without-warning" || exit 1

  head -n 21 "$P/skills" | mem local-skills || exit 1
  mem note project 'another plain note' || exit 1
  on 2026-06-29 where > "$P/plain" || exit 1
  on 2026-06-29 where task > "$P/routed" || exit 1
  assert_eq "$(wc -l < "$P/plain" | tr -d ' ')" 40 plain_cap
  assert_eq "$(wc -l < "$P/routed" | tr -d ' ')" 40 routed_cap
  assert_eq "$(sed -n '4p' "$P/routed")" "$(miss_line 2026-06-28)" warning_at_cap
  assert_eq "$(sed -n '39s/^- [^ ]* //p' "$P/plain")" 'a plain note' last_note
  assert_eq "$(tail -n 1 "$P/routed")" '...' routed_tail
  head -n 38 "$P/plain" > "$P/plain-top" || exit 1
  sed '4d;40d' "$P/routed" > "$P/routed-top" || exit 1
  cmp "$P/plain-top" "$P/routed-top" || exit 1
}

test_projects_keep_separate_state_including_spaces() {
  mk_home; proj 'my app'
  case "$s" in *" "*) ;; *) echo "slug has no space: $s"; exit 1 ;; esac
  start_task
  first_project=$P; first_state=$state
  proj other
  on 2026-06-28 where > "$P/plain" || exit 1
  on 2026-06-28 where task > "$P/routed" || exit 1
  cmp "$P/plain" "$P/routed" || exit 1
  assert_eq "$(cat "$state")" '2026-06-28 open' second_state
  assert_eq "$(cat "$first_state")" '2026-06-27 open' first_state
  P=$first_project
  out=$(on 2026-06-29 where task) || exit 1
  assert_eq "$(printf '%s\n' "$out" | sed -n '4p')" "$(miss_line 2026-06-27)" first_warning
  on 2026-06-29 closeout skipped >/dev/null || exit 1
  assert_eq "$(cat "$first_state")" '2026-06-27 missed
2026-06-29 closed' first_history
  assert_eq "$(cat "$state")" '2026-06-28 open' second_untouched
}

test_closeout_rejects_missing_and_unknown_words() {
  mk_home; proj app; start_task
  cp "$state" "$P/open" || exit 1
  for word in missing unknown; do
    set -- closeout
    [ "$word" = missing ] || set -- "$@" "$word"
    on 2026-06-27 "$@" >"$P/receipt" 2>"$P/error"
    assert_eq "$?" 2 "$word"
    cmp /dev/null "$P/receipt" || exit 1
    assert_eq "$(cat "$P/error")" 'usage: kaito-mem.sh closeout nothing_to_save|skipped' usage
    cmp "$P/open" "$state" || exit 1
  done
}

test_closeout_leaves_memory_and_pending_migration_untouched() {
  mk_home; proj app
  git -C "$P" init -q && git -C "$P" remote add origin https://github.com/example/closeout.git || exit 1
  memory_slug=$(on 2026-06-27 slug) || exit 1
  [ "$memory_slug" != "$s" ] || exit 1
  state="$KAITO_HOME/closeout/$memory_slug"
  start_task
  mkdir -p "$M/projects" || exit 1
  printf '%s\n' 'rule: keep the path-keyed rule' > "$f" &&
    printf '%s\n' "- projects/$s.md $P" > "$M/MEMORY.md" &&
    printf '%s\n' "2026-06-26 $s correction" > "$M/learning.log" &&
    printf '%s\n' 'rule: keep the global rule' > "$M/global.md" &&
    cp -R "$M" "$P/memory-before" || exit 1
  out=$(on 2026-06-27 closeout nothing_to_save) || exit 1
  assert_eq "$out" nothing_to_save receipt
  assert_eq "$(cat "$state")" '2026-06-27 closed' closed
  diff -r "$P/memory-before" "$M" || exit 1
}

test_closeout_without_an_open_task_succeeds() {
  mk_home; proj app
  out=$(on 2026-06-27 closeout skipped) || exit 1
  assert_eq "$out" skipped receipt
  assert_no "$KAITO_HOME/closeout"
  assert_no "$M"
  start_task
  on 2026-06-28 closeout skipped >/dev/null || exit 1
  cp "$state" "$P/closed" || exit 1
  out=$(on 2026-06-29 closeout nothing_to_save) || exit 1
  assert_eq "$out" nothing_to_save receipt
  cmp "$P/closed" "$state" || exit 1
}

test_read_only_kaito_home_keeps_where_and_capture_working() {
  skip_on_win "chmod cannot make a folder read-only" && return 0
  [ "$(id -u)" != 0 ] || { echo "skip: root ignores read-only folders"; return 0; }
  mk_home; proj app
  mkdir -p "$KAITO_HOME" "$HOME/writable-memory" || exit 1
  printf '%s\n' '{"memory":{"path":"~/writable-memory"}}' > "$KAITO_HOME/config.json" || exit 1
  assert_eq "$(mem dir)" "$HOME/writable-memory" custom_memory
  chmod 555 "$KAITO_HOME" || exit 1
  on 2026-06-27 where >"$P/plain" 2>"$P/plain-error"; plain_rc=$?
  on 2026-06-27 where task >"$P/routed" 2>"$P/routed-error"; routed_rc=$?
  printf '%s\n' 'save outside kaito home' | on 2026-06-27 capture convention >"$P/receipt" 2>"$P/error"
  capture_rc=$?
  chmod 755 "$KAITO_HOME" || exit 1
  assert_eq "$plain_rc" 0 plain
  assert_eq "$routed_rc" 0 routed
  cmp "$P/plain" "$P/routed" && cmp "$P/plain-error" "$P/routed-error" &&
    cmp /dev/null "$P/routed-error" || exit 1
  assert_eq "$capture_rc" 0 capture
  assert_eq "$(cat "$P/receipt")" saved receipt
  cmp /dev/null "$P/error" || exit 1
  assert_eq "$(cat "$HOME/writable-memory/projects/$s.md")" 'learn: convention 1 2026-06-27 save outside kaito home' learning
  assert_no "$KAITO_HOME/closeout"
  assert_no "$M"
}

test_start_drops_state_older_than_28_days() {
  mk_home; proj app
  for day in 2026-05-30 2026-05-31 2026-06-01; do
    on "$day" where task >/dev/null && on "$day" closeout skipped >/dev/null || exit 1
  done
  assert_eq "$(cat "$state")" '2026-05-30 closed
2026-05-31 closed
2026-06-01 closed' before_pruning
  on 2026-06-28 where task >/dev/null || exit 1
  assert_eq "$(cat "$state")" '2026-05-31 closed
2026-06-01 closed
2026-06-28 open' retained
}

test_stats_preserves_correction_rows_without_closeout_state() {
  mk_home; proj app; a=$s
  on 2026-06-01 learn correction one && on 2026-06-08 learn correction two &&
    on 2026-06-09 learn correction two && on 2026-06-25 learn correction three &&
    on 2026-06-28 learn worked 'a successful check' && on 2026-05-01 learn correction 'too old' || exit 1
  proj other; b=$s
  on 2026-06-27 learn correction elsewhere global || exit 1
  assert_no "$KAITO_HOME/closeout"
  out=$(on 2026-06-28 stats) || exit 1
  assert_eq "$out" "corrections per week, oldest first; the last week ends 2026-06-28
$a: 1 2 0 1
$b: 0 0 0 1
$(stats_line 0 0)" complete_stats
}

test_stats_counts_only_recent_missed_and_closed_starts() {
  mk_home; proj app
  expected="corrections per week, oldest first; the last week ends 2026-06-28
$s: 0 0 0 0"
  on 2026-05-31 where task >/dev/null && on 2026-05-31 closeout skipped >/dev/null || exit 1
  out=$(on 2026-06-28 stats) || exit 1
  assert_eq "$out" "$expected
$(stats_line 0 0)" age_28_excluded
  on 2026-06-01 where task >/dev/null && on 2026-06-01 closeout skipped >/dev/null || exit 1
  out=$(on 2026-06-28 stats) || exit 1
  assert_eq "$out" "$expected
$(stats_line 0 1)" age_27_included
  on 2026-06-27 where task >/dev/null || exit 1
  out=$(on 2026-06-28 stats) || exit 1
  assert_eq "$out" "$expected
$(stats_line 0 1)" still_open
  on 2026-06-28 where task >/dev/null || exit 1
  out=$(on 2026-06-28 stats) || exit 1
  assert_eq "$out" "$expected
$(stats_line 1 2)" next_start_detected_miss
}

test_closeout_rejects_an_extra_argument() {
  mk_home; proj app; start_task
  out=$(mem closeout skipped extra 2>/dev/null) && exit 1
  assert_eq "$out" "" stdout
  assert_eq "$(cat "$state")" '2026-06-27 open' still_open
}
