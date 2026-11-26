#!/bin/sh
. "$(dirname "$0")/lib.sh"
MC="$REPO/media-cleanup/scripts/media_cleanup.py"
DAY=2026-01-02

need_py() { command -v python3 >/dev/null 2>&1 || { echo "skip: python3 not installed"; return 1; }; }

# A job folder with a final, rebuild inputs and clutter.
mk_job() {
  JOB="$(mktemp -d)/job1"
  mkdir -p "$JOB/takes" "$JOB/parts" "$JOB/tmp"
  echo final > "$JOB/final.mp4"
  echo lines > "$JOB/lines.json"
  echo parts > "$JOB/parts/parts.json"
  echo t1 > "$JOB/takes/a.wav"
  echo t2 > "$JOB/takes/b.wav"
  echo junk > "$JOB/tmp/x.bin"
  echo junk > "$JOB/scratch.png"
  KEEP="$(mktemp -d)/keep.txt"
  printf '# final and rebuild inputs\nfinal.mp4\nlines.json\nparts\n' > "$KEEP"
}
files_of() { (cd "$1" && find . -type f -o -type l | sort); }

test_dry_run_lists_and_changes_nothing() {
  need_py || return 0
  mk_home; mk_job
  before=$(files_of "$JOB")
  out=$(python3 "$MC" clean "$JOB" --keep "$KEEP" --date $DAY) || exit 1
  assert_eq "$(files_of "$JOB")" "$before" job
  assert_no "$KAITO_HOME/trash"
  echo "$out" | grep -q 'would-move.*takes/a.wav' || { echo "$out"; exit 1; }
  echo "$out" | grep -q 'would-move.*scratch.png' || exit 1
  echo "$out" | grep -q 'keep .*final.mp4' || exit 1
  echo "$out" | grep -q 'dry run: nothing changed' || exit 1
  # --dry-run spelled out behaves the same
  python3 "$MC" clean "$JOB" --keep "$KEEP" --dry-run >/dev/null || exit 1
  assert_eq "$(files_of "$JOB")" "$before" job2
}

test_apply_moves_exactly_the_rest() {
  need_py || return 0
  mk_home; mk_job
  python3 "$MC" clean "$JOB" --keep "$KEEP" --apply --date $DAY >/dev/null || exit 1
  T="$KAITO_HOME/trash/$DAY/job1"
  assert_eq "$(files_of "$JOB")" "$(printf '%s\n' ./final.mp4 ./lines.json ./parts/parts.json)" kept
  assert_eq "$(files_of "$T")" "$(printf '%s\n' ./scratch.png ./takes/a.wav ./takes/b.wav ./tmp/x.bin)" trashed
  assert_no "$JOB/takes"
  assert_eq "$(cat "$T/takes/a.wav")" t1 content
}

test_empty_manifest_refused() {
  need_py || return 0
  mk_home; mk_job; : > "$KEEP"
  python3 "$MC" clean "$JOB" --keep "$KEEP" --apply >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 3 rc
  assert_file "$JOB/scratch.png"
}

test_manifest_outside_job_refused() {
  need_py || return 0
  mk_home; mk_job; echo '../other' > "$KEEP"
  python3 "$MC" clean "$JOB" --keep "$KEEP" --apply >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 1 rc
  assert_file "$JOB/scratch.png"
}

test_tracked_files_untouched() {
  need_py || return 0
  mk_home; mk_job
  git -C "$JOB" init -q 2>/dev/null || exit 1
  git -C "$JOB" add scratch.png
  git -C "$JOB" -c user.name=t -c user.email=t@example.com commit -qm t || exit 1
  out=$(python3 "$MC" clean "$JOB" --keep "$KEEP" --apply --date $DAY) || exit 1
  assert_file "$JOB/scratch.png"
  echo "$out" | grep -q 'tracked .*scratch.png' || { echo "$out"; exit 1; }
  assert_no "$KAITO_HOME/trash/$DAY/job1/scratch.png"
  assert_file "$KAITO_HOME/trash/$DAY/job1/takes/a.wav"
}

test_escaping_symlink_refused() {
  need_py || return 0
  skip_on_win "symlinks" && return 0
  mk_home; mk_job
  outside="$(mktemp -d)"; echo secret > "$outside/secret.txt"
  ln -s "$outside" "$JOB/linkdir"
  ln -s "$outside/secret.txt" "$JOB/linkfile"
  before=$(files_of "$JOB")
  out=$(python3 "$MC" clean "$JOB" --keep "$KEEP" --apply --date $DAY 2>&1); rc=$?
  assert_eq "$rc" 3 rc
  echo "$out" | grep -q 'REFUSED.*linkdir' || { echo "$out"; exit 1; }
  echo "$out" | grep -q 'REFUSED.*linkfile' || exit 1
  assert_eq "$(files_of "$JOB")" "$before" untouched
  assert_eq "$(cat "$outside/secret.txt")" secret outside
  assert_no "$KAITO_HOME/trash"
}

test_inside_symlink_moves_as_link() {
  need_py || return 0
  skip_on_win "symlinks" && return 0
  mk_home; mk_job
  ln -s takes/a.wav "$JOB/alias.wav"
  python3 "$MC" clean "$JOB" --keep "$KEEP" --apply --date $DAY >/dev/null || exit 1
  assert_no "$JOB/alias.wav"
  [ -L "$KAITO_HOME/trash/$DAY/job1/alias.wav" ] || { echo "link not moved as a link"; exit 1; }
}

test_purge_needs_yes() {
  need_py || return 0
  mk_home
  mkdir -p "$KAITO_HOME/trash/2025-01-01/j" "$KAITO_HOME/trash/2026-11-20/j" "$KAITO_HOME/trash/notadate"
  echo a > "$KAITO_HOME/trash/2025-01-01/j/a"; echo b > "$KAITO_HOME/trash/2026-11-20/j/b"
  python3 "$MC" purge --older-than 30d --today 2026-11-26 >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 3 rc
  assert_file "$KAITO_HOME/trash/2025-01-01/j/a"
  python3 "$MC" purge --older-than 30d --today 2026-11-26 --yes >/dev/null || exit 1
  assert_no "$KAITO_HOME/trash/2025-01-01"
  assert_file "$KAITO_HOME/trash/2026-11-20/j/b"
  assert_file "$KAITO_HOME/trash/notadate"
}

test_worktrees_only_clean_merged_removed() {
  need_py || return 0
  mk_home
  base="$(mktemp -d)"
  R="$base/repo"
  g() { git -C "$R" -c user.name=t -c user.email=t@example.com "$@"; }
  git init -q -b main "$R" || exit 1
  echo a > "$R/a"; g add a; g commit -qm one
  # merged and clean
  g worktree add -q -b merged-clean "$base/wt-merged-clean" || exit 1
  # merged but dirty
  g worktree add -q -b merged-dirty "$base/wt-merged-dirty" || exit 1
  echo x > "$base/wt-merged-dirty/untracked"
  # clean but not merged
  g worktree add -q -b ahead "$base/wt-ahead" || exit 1
  echo b > "$base/wt-ahead/b"
  git -C "$base/wt-ahead" add b
  git -C "$base/wt-ahead" -c user.name=t -c user.email=t@example.com commit -qm two
  # list only
  out=$(python3 "$MC" worktrees "$R") || exit 1
  echo "$out" | grep -q 'REMOVE.*wt-merged-clean' || { echo "$out"; exit 1; }
  echo "$out" | grep -q 'keep.*wt-merged-dirty.*not clean' || { echo "$out"; exit 1; }
  echo "$out" | grep -q 'keep.*wt-ahead.*not merged' || { echo "$out"; exit 1; }
  echo "$out" | grep -q 'main .*repo.*main checkout' || { echo "$out"; exit 1; }
  assert_file "$base/wt-merged-clean"
  # apply
  python3 "$MC" worktrees "$R" --apply >/dev/null || exit 1
  assert_no "$base/wt-merged-clean"
  assert_file "$base/wt-merged-dirty/untracked"
  assert_file "$base/wt-ahead/b"
  assert_file "$R/a"
  case "$(g worktree list)" in *wt-merged-clean*) echo "still registered"; exit 1;; esac
}

test_guards_date_dot_abbrev_ignored() {
  need_py || return 0
  mk_home; mk_job
  python3 "$MC" clean "$JOB" --keep "$KEEP" --apply --date ../../x >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 2 baddate
  assert_file "$JOB/scratch.png"
  echo . > "$KEEP"
  python3 "$MC" clean "$JOB" --keep "$KEEP" --apply --date $DAY >/dev/null || exit 1
  assert_file "$JOB/scratch.png"
  assert_no "$KAITO_HOME/trash"
  mkdir -p "$KAITO_HOME/trash/2020-01-01/j"; echo a > "$KAITO_HOME/trash/2020-01-01/j/a"
  python3 "$MC" purge --older-than 30d --y >/dev/null 2>&1 && exit 1
  assert_file "$KAITO_HOME/trash/2020-01-01/j/a"
  # an ignored file keeps its worktree from being removed
  base="$(mktemp -d)"; R="$base/repo"
  git init -q -b main "$R" || exit 1
  echo a > "$R/a"; echo 'render.mp4' > "$R/.gitignore"
  git -C "$R" add a .gitignore
  git -C "$R" -c user.name=t -c user.email=t@example.com commit -qm one
  git -C "$R" worktree add -q -b done "$base/wt" || exit 1
  echo big > "$base/wt/render.mp4"
  python3 "$MC" worktrees "$R" --apply >/dev/null || exit 1
  assert_file "$base/wt/render.mp4"
}
