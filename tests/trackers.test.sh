#!/bin/sh
. "$(dirname "$0")/lib.sh"
T="$REPO/helpmekaito/scripts/kaito-tasks.sh"
MEMSH="$REPO/helpmekaito/scripts/kaito-mem.sh"
PK=plane_api_FAKEKEY0123456789
P1=11111111-1111-4111-8111-111111111111
MOD=33333333-3333-4333-8333-333333333333

# home <manager>: temp home, config default manager, a git repo "proj" as cwd
home() {
  mk_home; mkdir -p "$KAITO_HOME" "$HOME/proj"; cd "$HOME/proj" || exit 1
  printf '{"tasks":{"manager":"%s","state":"done"}}\n' "$1" > "$KAITO_HOME/config.json"
  MEM="$KAITO_HOME/memory"
  sl=$(sh "$REPO/helpmekaito/scripts/kaito-codegraph.sh" slug "$HOME/proj"); PF="$MEM/projects/$sl.md"
}
plane_stub() {
  LOG="$HOME/log.jsonl"; : > "$LOG"; rm -f "$HOME/port"
  SPID=$(sh -c 'node "$@" >/dev/null 2>&1 & echo $!' _ "$TESTS_DIR/stubs/plane-api.mjs" "$LOG" "$HOME/port")
  trap 'kill $SPID 2>/dev/null' EXIT
  i=0; while [ ! -s "$HOME/port" ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done
  KAITO_PLANE_API="http://127.0.0.1:$(cat "$HOME/port")/api/v1"; export KAITO_PLANE_API
  printf 'PLANE_API_KEY=%s\nPLANE_WORKSPACE=acme\n' "$PK" > "$KAITO_HOME/.env"
}
repo() { git init -q . && git -c user.email=t@example.test -c user.name=t commit -q --allow-empty -m "${1:-init}"; }
has() { case "$1" in *"$2"*) ;; *) echo "  missing '$2' in: $1"; exit 1 ;; esac; }
hasnt() { case "$1" in *"$2"*) echo "  unexpected '$2' in: $1"; exit 1 ;; esac; }
# plane_map: a stored Plane structure with project ALL and module Kaito Skills, as discover would write it
plane_map() {
  mkdir -p "$MEM/managers"
  printf '{"generated_at":"%s","boards":{"%s":{"name":"ALL","identifier":"ALL","states":[],"modules":[{"id":"%s","name":"Kaito Skills"}],"labels":[],"members":[]}}}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$P1" "$MOD" > "$MEM/managers/plane.json"
}

test_two_trackers_with_roles_and_settings() {
  home none
  sh "$T" tracker add plane "$P1/$MOD" "ALL / Kaito Skills" role=official tracking=always >/dev/null || exit 1
  sh "$T" tracker add obsidian - "Work log" role=personal "note=my own notes, not team tickets" >/dev/null || exit 1
  out=$(sh "$T" tracker list)
  has "$out" "tracker: plane $P1/$MOD ALL / Kaito Skills | role=official | tracking=always"
  has "$out" "tracker: obsidian - Work log | role=personal | tracking=ask | note=my own notes, not team tickets"
  sh "$T" tracker set obsidian tracking=never >/dev/null || exit 1
  has "$(sh "$T" tracker list)" "obsidian - Work log | role=personal | tracking=never"
  has "$(sh "$T" tracker list)" "plane $P1/$MOD ALL / Kaito Skills | role=official | tracking=always"
  has "$(sh "$MEMSH" where | sed -n 4,5p)" "tracker: "   # project facts come first, before any cut
  sh "$T" tracker rm obsidian >/dev/null || exit 1
  hasnt "$(sh "$T" tracker list)" obsidian
}

test_tracker_rejects_bad_input_and_secrets() {
  home none
  sh "$T" tracker add 'pl ane' x >/dev/null 2>&1 && { echo "  bad manager"; exit 1; }
  sh "$T" tracker add plane 'a b' >/dev/null 2>&1 && { echo "  bad id"; exit 1; }
  sh "$T" tracker add plane "$P1" ALL role=boss >/dev/null 2>&1 && { echo "  bad role"; exit 1; }
  sh "$T" tracker add plane "$P1" ALL tracking=sometimes >/dev/null 2>&1 && { echo "  bad tracking"; exit 1; }
  sh "$T" tracker add plane "$P1" ALL "note=token: abcdefabcdef1234" >/dev/null 2>&1 && { echo "  secret stored"; exit 1; }
  sh "$T" tracker set jira tracking=always >/dev/null 2>&1 && { echo "  set on a missing tracker"; exit 1; }
  assert_no "$PF"
  # a name cannot smuggle in a second line or a setting
  sh "$T" tracker add plane "$P1" "ALL | tracking=always
tracker: evil x y" >/dev/null || exit 1
  assert_eq "$(grep -c '^tracker: ' "$PF" | tr -d ' ')" 1 "one line"
  has "$(sh "$T" tracker list)" "tracking=ask"
}

test_old_board_line_reads_as_official_tracker() {
  home trello; mkdir -p "$MEM/projects"; echo "board: trello b1 Work" > "$PF"; echo "- 2026-11-01 a note" >> "$PF"
  assert_eq "$(sh "$T" tracker list)" "tracker: trello b1 Work | role=official | tracking=ask" legacy
  sh "$T" tracker set trello tracking=always >/dev/null || exit 1
  assert_eq "$(grep -c '^board: ' "$PF" | tr -d ' ')" 0 "board line converted"
  grep -qx "tracker: trello b1 Work | role=official | tracking=always" "$PF" || { cat "$PF"; exit 1; }
  grep -qx -- "- 2026-11-01 a note" "$PF" || { echo "  lost a note"; cat "$PF"; exit 1; }
}

test_board_none_and_tracking_never_stop_reads_and_writes() {
  home obsidian; mkdir -p "$MEM/projects"; echo "board: none" > "$PF"
  out=$(sh "$T" add "Should not exist" 2>&1) && { echo "  write allowed"; exit 1; }
  has "$out" "tracking is off"
  out=$(sh "$T" list) || { echo "  list should exit 0"; exit 1; }
  has "$out" "tracking is off"
  assert_no "$MEM/tasks"
  rm "$PF"; sh "$T" tracking never >/dev/null || exit 1
  sh "$T" add "Still not" >/dev/null 2>&1 && { echo "  write allowed after tracking never"; exit 1; }
  sh "$T" tracking ask >/dev/null || exit 1
  sh "$T" add "Now it works" >/dev/null || { echo "  write refused after tracking ask"; exit 1; }
}

test_tracking_never_on_one_tracker_leaves_the_other() {
  home none; plane_stub
  sh "$T" tracker add plane "$P1" ALL tracking=never >/dev/null
  sh "$T" tracker add obsidian - Notes role=personal tracking=always >/dev/null || exit 1
  sh "$T" --tracker plane add "No ticket" >/dev/null 2>&1 && { echo "  plane write allowed"; exit 1; }
  assert_eq "$(grep -c . "$LOG" | tr -d ' ')" 0 "no request to Plane"
  out=$(sh "$T" --tracker obsidian add "My own note") || { echo "  obsidian refused"; exit 1; }
  has "$out" "added t-"
}

test_list_groups_by_tracker_and_tracker_flag_picks_one() {
  home none; plane_stub
  sh "$T" tracker add plane "$P1/$MOD" "ALL / Kaito Skills" tracking=always >/dev/null
  sh "$T" tracker add obsidian - Notes role=personal tracking=always >/dev/null || exit 1
  sh "$T" --tracker obsidian add "Personal reminder" >/dev/null || exit 1
  sh "$T" --tracker plane pull >/dev/null || { echo "  pull failed"; exit 1; }
  out=$(sh "$T" list)
  has "$out" "## plane"; has "$out" "ALL-1 To Do Add Plane support"; has "$out" "## obsidian"; has "$out" "Personal reminder"
  out=$(sh "$T" --tracker obsidian list); hasnt "$out" "ALL-1"; has "$out" "Personal reminder"
  # with no flag a write goes to the first scripted tracker
  has "$(sh "$T" add "Team ticket")" "added ALL-7 Team ticket"
  sh "$T" --tracker jira list >/dev/null 2>&1 && { echo "  unknown tracker accepted"; exit 1; }
  :
}

test_mcp_tracker_points_at_the_mcp() {
  home none
  sh "$T" tracker add jira KAI "Kaito on acme" tracking=always >/dev/null || exit 1
  assert_eq "$(sh "$T" list)" "use the jira MCP; see references/tasks.md" msg
}

test_map_keeps_tracker_settings() {
  home plane; plane_stub
  sh "$T" tracker add plane "$P1" ALL role=official tracking=always "note=team tickets" >/dev/null || exit 1
  sh "$T" map "$P1/$MOD" >/dev/null || { echo "  map failed"; exit 1; }
  assert_eq "$(sh "$T" tracker list)" "tracker: plane $P1/$MOD ALL / Kaito Skills | role=official | tracking=always | note=team tickets" kept
  assert_eq "$(grep -c '^board: ' "$PF" | tr -d ' ')" 0 "no board line beside tracker lines"
}

test_detect_strong_from_branch_key() {
  home none; plane_map; repo; git checkout -q -b ALL-27-plane-support
  out=$(sh "$T" detect)
  has "$out" "candidate: plane $P1 ALL | strength=strong | evidence=branch ALL-27-plane-support carries the key ALL"
  has "$out" "known: plane"
  assert_no "$PF"   # detect never maps
}

test_detect_weak_from_name_and_one_commit() {
  home none; plane_map
  mkdir -p "$HOME/kaito-skills"; cd "$HOME/kaito-skills" || exit 1; repo "ALL-3 first commit"
  out=$(sh "$T" detect)
  has "$out" "candidate: plane $P1/$MOD ALL / Kaito Skills | strength=weak | evidence=the repo is named like the module"
  has "$out" "candidate: plane $P1 ALL | strength=weak | evidence=1 of the last 1 commits carry the key ALL"
  hasnt "$out" "strength=strong"
}

test_detect_links_in_repo_docs() {
  home none; plane_map; repo
  printf 'Board: https://trello.com/b/AbCd1234/team-board\nTickets: https://acme.atlassian.net/browse/KAI-12\nPlane: https://app.plane.so/acme/projects/%s/modules/%s/\n' "$P1" "$MOD" > README.md
  out=$(sh "$T" detect)
  has "$out" "candidate: trello AbCd1234 team-board | strength=strong | evidence=README.md links the board"
  has "$out" "candidate: jira KAI KAI on acme.atlassian.net | strength=strong"
  has "$out" "candidate: plane $P1/$MOD ALL | strength=strong | evidence=README.md links the project"
}

test_detect_does_not_guess() {
  home none; plane_map; repo "PR-12 and UTF-8 and ALLY-3 are not project keys"
  git checkout -q -b fix-sha-256-check
  out=$(sh "$T" detect)
  has "$out" "candidate: none"
  # with no structure map nothing is matched by name or key either
  rm -r "$MEM/managers"; git checkout -q -b ALL-9-x
  out=$(sh "$T" detect); has "$out" "candidate: none"; has "$out" "known: none"
}

test_crlf_tracker_lines_are_read_and_kept() {
  home none; mkdir -p "$MEM/projects"
  printf 'tracker: plane %s ALL | role=official | tracking=never\r\nnotes line\r\n' "$P1" > "$PF"
  has "$(sh "$T" tracker list)" "tracker: plane $P1 ALL | role=official | tracking=never"
  sh "$T" tracker add obsidian - Notes role=personal >/dev/null || exit 1
  out=$(sh "$T" tracker list); has "$out" "tracker: plane $P1 ALL"; has "$out" "tracker: obsidian"
}

test_remap_keeps_the_default_tracker_first() {
  home none; plane_stub
  sh "$T" tracker add plane "$P1" ALL >/dev/null; sh "$T" tracker add obsidian - Notes role=personal >/dev/null || exit 1
  sh "$T" --tracker plane map "$P1/$MOD" >/dev/null || { echo "  map failed"; exit 1; }
  has "$(sh "$T" tracker list | head -1)" "tracker: plane $P1/$MOD"
}

test_detect_keeps_the_linked_trello_board() {
  home none; repo; mkdir -p "$MEM/managers"
  printf '{"boards":{"5f00000000000000000000aa":{"name":"Team Board"}}}\n' > "$MEM/managers/trello.json"
  printf 'Board: https://trello.com/b/AbCd1234/team-board\n' > README.md
  out=$(sh "$T" detect)
  has "$out" "candidate: trello AbCd1234 team-board | strength=strong"
  hasnt "$out" "5f00000000000000000000aa | strength=strong"
}
