#!/bin/sh
. "$(dirname "$0")/lib.sh"
T="$REPO/helpmekaito/scripts/kaito-tasks.sh"
JS="$REPO/helpmekaito/scripts/kaito-json.mjs"
LK=lin_api_FAKEKEY0123456789
T1=11111111-1111-4111-8111-111111111111
T2=22222222-2222-4222-8222-222222222222
PJ=33333333-3333-4333-8333-333333333333
PJDONE=44444444-4444-4444-8444-444444444444
ME=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
K1=00000000-0000-4000-8000-000000000001  # KAI-1's id in the stub

# stub: starts the fake Linear, sets LOG, SPID, KAITO_LINEAR_API; stops it when the test exits
stub() {
  LOG="$HOME/log.jsonl"; : > "$LOG"; rm -f "$HOME/port"
  SPID=$(sh -c 'node "$@" >/dev/null 2>&1 & echo $!' _ "$TESTS_DIR/stubs/linear-api.mjs" "$LOG" "$HOME/port")
  trap 'kill $SPID 2>/dev/null' EXIT
  i=0; while [ ! -s "$HOME/port" ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done
  KAITO_LINEAR_API="http://127.0.0.1:$(cat "$HOME/port")/graphql"; export KAITO_LINEAR_API
}
# home: temp home with manager linear (or $1), the stub, a fake key, project folder as cwd
home() {
  mk_home; mkdir -p "$KAITO_HOME" "$HOME/proj"; cd "$HOME/proj" || exit 1
  printf '{"tasks":{"manager":"%s","state":"pending"}}\n' "${1:-linear}" > "$KAITO_HOME/config.json"
  stub; printf 'TRELLO_KEY=keepme\nLINEAR_API_KEY=%s\n' "$LK" > "$KAITO_HOME/.env"
  MEM="$KAITO_HOME/memory"
  sl=$(sh "$REPO/helpmekaito/scripts/kaito-codegraph.sh" slug "$HOME/proj"); CACHE="$MEM/tasks/linear/$sl"; PF="$MEM/projects/$sl.md"
}
count() { node -e 'const [f,o]=process.argv.slice(1);console.log(require("fs").readFileSync(f,"utf8").split("\n").filter(Boolean).map(JSON.parse).filter(e=>e.op===o).length)' "$LOG" "$1"; }
last() { _lo=$1; shift; node -e 'const [f,o,...ks]=process.argv.slice(1);const e=require("fs").readFileSync(f,"utf8").split("\n").filter(Boolean).map(JSON.parse).filter(e=>e.op===o).pop();console.log(e?ks.map(k=>{const v=k.split(".").reduce((x,y)=>x?.[y],e);return Array.isArray(v)?v.join():String(v)}).join(" "):"none")' "$LOG" "$_lo" "$@"; }
# attachments <issue>: how many the stub holds for that issue
attachments() { node -e 'fetch(process.argv[1],{method:"POST",headers:{authorization:"x","content-type":"application/json"},body:JSON.stringify({query:"query StubAttachments { x }",variables:{id:process.argv[2]}})}).then(r=>r.json()).then(j=>console.log(j.data.count))' "$KAITO_LINEAR_API" "$1"; }
has() { case "$1" in *"$2"*) ;; *) echo "  missing '$2' in: $1"; exit 1 ;; esac; }

test_status_never_prints_the_key() {
  home; sh "$T" map "$T1/$PJ" >/dev/null || exit 1
  out=$(sh "$T" status 2>&1)
  case "$out" in *"$LK"*) echo "  leaked"; exit 1;; esac
  printf "%s\n" "$out" | grep -qx "manager: linear" || { echo "$out"; exit 1; }
  printf "%s\n" "$out" | grep -qx "credentials: yes ($KAITO_HOME/.env)" || { echo "$out"; exit 1; }
  printf "%s\n" "$out" | grep -qx "board: linear $T1/$PJ Kaito / Kaito Skills" || { echo "$out"; exit 1; }
  out=$(LINEAR_API_KEY=$LK sh "$T" status 2>&1); printf "%s\n" "$out" | grep -qx "credentials: yes (env)" || { echo "$out"; exit 1; }
}

test_no_key_points_at_login_and_mcp() {
  home; rm "$KAITO_HOME/.env"
  out=$(sh "$T" boards 2>&1) && { echo "  should fail"; exit 1; }
  has "$out" "login"; has "$out" "Linear MCP"
  assert_eq "$(grep -c . "$LOG" | tr -d ' ')" 0 "no request without a key"
}

test_login_refuses_without_tty() {
  home
  out=$(sh "$T" login </dev/null 2>&1) && { echo "  should fail"; exit 1; }
  has "$out" "run it in a terminal"
}

test_boards_and_projects_list_by_name() {
  home
  out=$(sh "$T" boards) || exit 1
  assert_eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 2 "two teams"
  has "$out" "$T1 KAI Kaito"; has "$out" "$T2 PER Personal"
  assert_eq "$(sh "$T" projects "$T1")" "$T1/$PJ Kaito Skills" "open projects only"
  sh "$T" projects 'a b' >/dev/null 2>&1 && { echo "  bad team id accepted"; exit 1; }
  sh "$T" modules "$T1" >/dev/null 2>&1 && { echo "  modules is for Plane"; exit 1; }
  :
}

test_map_rejects_bad_ids() {
  home
  for b in "" "a b" "$T1/$PJ/x" "/$PJ" "$T1/" '$(id)' KAI "$T1/KAI"; do
    sh "$T" map "$b" >/dev/null 2>&1 && { echo "  accepted '$b'"; exit 1; }
  done
  sh "$T" map "$T1/$PJDONE" >/dev/null 2>&1 && { echo "  mapped a completed project"; exit 1; }
  assert_no "$PF"
}

test_map_team_and_project() {
  home
  assert_eq "$(sh "$T" map "$T1")" "board: linear $T1 Kaito" team
  assert_eq "$(sh "$T" map "$T1/$PJ")" "board: linear $T1/$PJ Kaito / Kaito Skills" project
  assert_eq "$(grep -c '^board: ' "$PF" | tr -d ' ')" 1 "one board line"
}

test_pull_whole_team_groups_children() {
  home; sh "$T" map "$T1" >/dev/null || exit 1
  out=$(sh "$T" pull) || { echo "  pull failed"; exit 1; }
  assert_eq "$out" "pulled 3 issues" count   # KAI-1, KAI-4, KAI-5: children, closed and archived are not files
  f="$CACHE/KAI-1-add-linear-support.md"; assert_file "$f"
  grep -q '^list: "To Do"$' "$f" || { cat "$f"; exit 1; }
  grep -q '^state_group: "unstarted"$' "$f" || { cat "$f"; exit 1; }
  grep -q '^due: "2026-12-01"$' "$f" || { cat "$f"; exit 1; }
  grep -q '^labels: "bug"$' "$f" || { cat "$f"; exit 1; }
  grep -q '^url: "https://linear.app/acme/issue/KAI-1/' "$f" || { cat "$f"; exit 1; }
  grep -qx 'private words alpha' "$f" || { echo "  description not kept"; cat "$f"; exit 1; }
  grep -q -- '- \[ \] Write the client <!-- id:KAI-2 -->' "$f" || { cat "$f"; exit 1; }
  grep -q -- '- \[x\] Write the tests <!-- id:KAI-3 -->' "$f" || { cat "$f"; exit 1; }
  assert_no "$CACHE/KAI-2-write-the-client.md"; assert_no "$CACHE/KAI-6-old-shipped-thing.md"; assert_no "$CACHE/KAI-7-archived-idea.md"
  out=$(sh "$T" list)
  has "$out" "KAI-1 To Do Add Linear support (1 open)"; has "$out" "KAI-4 In Progress Migrate to Linear"; has "$out" "KAI-5 To Do Company admin"
  assert_eq "$(last Issues vars.filter.team.id.eq vars.filter.state.type.nin)" "$T1 completed,canceled,duplicate" filter
}

test_pull_project_scope_and_pagination() {
  home; kill $SPID; STUB_PAGE=2 stub
  sh "$T" map "$T1/$PJ" >/dev/null || exit 1
  assert_eq "$(sh "$T" pull)" "pulled 2 issues" "project holds KAI-1 and KAI-4"
  assert_eq "$(last Issues vars.filter.project.id.eq)" "$PJ" "project filter"
  assert_no "$CACHE/KAI-5-company-admin.md"
  grep -q -- 'id:KAI-2 -->' "$CACHE/KAI-1-add-linear-support.md" || { echo "  sub-issue outside the project lost"; exit 1; }
  sh "$T" map "$T1" >/dev/null; : > "$LOG"
  assert_eq "$(sh "$T" pull)" "pulled 3 issues" "whole team"
  assert_eq "$(count Issues)" 2 "4 open issues at 2 a page"
  assert_eq "$(last Issues vars.first vars.after)" "50 2" "cursor followed"
}

test_many_sub_issues_are_all_listed() {
  home; kill $SPID; STUB_KIDS=1 stub
  sh "$T" map "$T1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  f="$CACHE/KAI-1-add-linear-support.md"
  grep -q -- 'id:KAI-2 -->' "$f" && grep -q -- 'id:KAI-3 -->' "$f" || { cat "$f"; exit 1; }
  assert_eq "$(last Children vars.id)" "$K1" "rest read page by page"
}

test_pull_failure_keeps_cache() {
  home; sh "$T" map "$T1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  kill $SPID; STUB_FAIL="Issues 500 5" stub
  out=$(sh "$T" pull 2>&1) && { echo "  should fail"; exit 1; }
  has "$out" "linear 500 Issues"
  assert_eq "$(count Issues)" 2 "a read retries once"
  assert_file "$CACHE/KAI-1-add-linear-support.md"
}

test_add_goes_to_todo_and_into_the_project() {
  home; sh "$T" map "$T1/$PJ" >/dev/null; sh "$T" consent yes "$T1" >/dev/null; sh "$T" discover >/dev/null || exit 1
  out=$(sh "$T" add "Ship the provider" --due 2026-12-24 --desc "First **line**") || { echo "  add failed: $out"; exit 1; }
  assert_eq "$out" "added KAI-8 Ship the provider" msg
  assert_eq "$(last IssueCreate vars.input.title vars.input.stateId vars.input.dueDate)" "Ship the provider s-todo 2026-12-24" input
  assert_eq "$(last IssueCreate vars.input.description)" "First **line**" "description stays Markdown"
  assert_eq "$(last IssueCreate vars.input.teamId vars.input.projectId vars.input.assigneeId)" "$T1 $PJ $ME" "team, project, me"
  assert_eq "$(count IssueCreate)" 1 "created once"
  assert_file "$CACHE/KAI-8-ship-the-provider.md"
  sh "$T" add "Later" --list Backlog >/dev/null || exit 1
  assert_eq "$(last IssueCreate vars.input.stateId)" "s-backlog" "--list by name"
}

test_sub_items_add_check_uncheck() {
  home; sh "$T" map "$T1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  assert_eq "$(sh "$T" item add KAI-1 "Write the docs")" "ok KAI-1" add
  assert_eq "$(last IssueCreate vars.input.parentId vars.input.stateId)" "$K1 s-todo" "sub-issue of KAI-1"
  f="$CACHE/KAI-1-add-linear-support.md"
  grep -q -- '- \[ \] Write the docs <!-- id:KAI-8 -->' "$f" || { cat "$f"; exit 1; }
  grep -q -- '- \[x\] Write the tests <!-- id:KAI-3 -->' "$f" || { echo "  lost a sibling"; cat "$f"; exit 1; }
  assert_eq "$(sh "$T" check KAI-1 KAI-2)" "ok KAI-1" check
  assert_eq "$(last IssueUpdate vars.input.stateId)" "s-done" "sub-issue moved to the completed state"
  grep -q -- '- \[x\] Write the client <!-- id:KAI-2 -->' "$f" || { cat "$f"; exit 1; }
  sh "$T" uncheck KAI-1 kai-2 >/dev/null || exit 1
  assert_eq "$(last IssueUpdate vars.input.stateId)" "s-todo" "sub-issue back to to-do"
  grep -q -- '- \[ \] Write the client <!-- id:KAI-2 -->' "$f" || { cat "$f"; exit 1; }
}

test_rename_move_comment_done_reopen() {
  home; sh "$T" map "$T1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  sh "$T" rename KAI-4 "Move everything to Linear" >/dev/null || exit 1
  assert_eq "$(last IssueUpdate vars.input.title)" "Move everything to Linear" title
  assert_file "$CACHE/KAI-4-move-everything-to-linear.md"; assert_no "$CACHE/KAI-4-migrate-to-linear.md"
  sh "$T" move KAI-4 "to do" >/dev/null || exit 1
  assert_eq "$(last IssueUpdate vars.input.stateId)" "s-todo" "move by state name"
  sh "$T" comment KAI-4 "Done in <PR 12> & **merged**" >/dev/null || exit 1
  assert_eq "$(last CommentCreate vars.input.body)" "Done in <PR 12> & **merged**" "comment is plain Markdown"
  sh "$T" done KAI-4 >/dev/null || exit 1
  assert_eq "$(last IssueUpdate vars.input.stateId)" "s-done" done
  assert_no "$CACHE/KAI-4-move-everything-to-linear.md"
  assert_eq "$(sh "$T" reopen KAI-4)" "ok KAI-4" "reopen by key, not in cache"
  assert_file "$CACHE/KAI-4-move-everything-to-linear.md"
  sh "$T" move KAI-4 Nowhere >/dev/null 2>&1 && { echo "  unknown state accepted"; exit 1; }
  out=$(sh "$T" done KAI-99 2>&1) && { echo "  unknown issue accepted"; exit 1; }
  has "$out" "no issue KAI-99"
}

test_done_without_completed_state_fails_clearly() {
  home; kill $SPID; STUB_NODONE=1 stub
  sh "$T" map "$T1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  out=$(sh "$T" done KAI-4 2>&1) && { echo "  should fail"; exit 1; }
  has "$out" "no completed state"
  assert_eq "$(count IssueUpdate)" 0 "nothing written"
}

test_writes_never_retry_and_remote_ok_is_reported() {
  home; sh "$T" map "$T1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  kill $SPID; STUB_FAIL="IssueCreate 500 1" stub
  sh "$T" add "Once only" >/dev/null 2>&1 && { echo "  should fail"; exit 1; }
  assert_eq "$(count IssueCreate)" 1 "no retry on a write"
  kill $SPID; STUB_FAIL="Issue 500 5" stub
  out=$(sh "$T" comment KAI-4 "note")
  has "$out" "remote ok (KAI-4), local refresh failed: run pull"
  assert_eq "$(count CommentCreate)" 1 "commented once"
}

test_discover_needs_consent_and_stores_no_issue_text() {
  home; sh "$T" map "$T1" >/dev/null
  sh "$T" discover >/dev/null 2>&1 && { echo "  discover without consent"; exit 1; }
  sh "$T" consent yes "$T1" >/dev/null && sh "$T" discover >/dev/null || { echo "  discover failed"; exit 1; }
  j="$MEM/managers/linear.json"; assert_file "$j"; assert_file "$MEM/managers/linear.md"
  assert_eq "$(node "$JS" get "$j" "boards.$T1.identifier")" '"KAI"' identifier
  assert_eq "$(node "$JS" get "$j" workspace)" '"acme"' workspace
  assert_eq "$(node "$JS" get "$j" me.id)" "\"$ME\"" me
  grep -q '"group": "completed"' "$j" || { echo "  no state types"; exit 1; }
  assert_eq "$(node "$JS" get "$j" "boards.$T1.modules.0.name")" '"Kaito Skills"' "projects under modules"
  grep -q 'Shipped Project' "$j" && { echo "  completed project stored"; exit 1; }
  grep -q 'private words\|Add Linear support\|Migrate to Linear' "$j" "$MEM/managers/linear.md" && { echo "  issue text stored"; exit 1; }
  case "$(cat "$j" "$MEM/managers/linear.md")" in *"$LK"*) echo "  key stored"; exit 1;; esac
  assert_eq "$(cfg_get tasks.discovery_linear.consent)" '"yes"' "consent kept per manager"
}
cfg_get() { node "$JS" get "$KAITO_HOME/config.json" "$1"; }

test_unknown_state_refreshes_structure_once() {
  home; sh "$T" map "$T1" >/dev/null; sh "$T" consent yes "$T1" >/dev/null; sh "$T" discover >/dev/null; sh "$T" pull >/dev/null || exit 1
  j="$MEM/managers/linear.json"
  # the stored map loses a state, as if it had been added in Linear after discovery
  node -e 'const fs=require("fs"),[f,p]=process.argv.slice(1);const m=JSON.parse(fs.readFileSync(f));m.boards[p].states=m.boards[p].states.filter(s=>s.name!=="In Progress");fs.writeFileSync(f,JSON.stringify(m))' "$j" "$T1"
  : > "$LOG"
  sh "$T" move KAI-5 "In Progress" >/dev/null || { echo "  move failed"; exit 1; }
  assert_eq "$(last IssueUpdate vars.input.stateId)" "s-doing" state
  assert_eq "$(count States)" 1 "read once"
  grep -q '"In Progress"' "$j" || { echo "  map not updated"; exit 1; }
}

test_stale_structure_refreshes_on_pull() {
  home; sh "$T" map "$T1" >/dev/null; sh "$T" consent yes "$T1" >/dev/null; sh "$T" discover >/dev/null || exit 1
  j="$MEM/managers/linear.json"
  sh "$T" pull >/dev/null; n=$(count Labels)
  assert_eq "$n" 1 "a fresh map is left alone"
  node -e 'const fs=require("fs"),f=process.argv[1];const m=JSON.parse(fs.readFileSync(f));m.generated_at="2020-01-01T00:00:00.000Z";fs.writeFileSync(f,JSON.stringify(m))' "$j"
  sh "$T" pull >/dev/null || { echo "  pull failed"; exit 1; }
  assert_eq "$(count Labels)" 2 "a stale map is rediscovered"
  case "$(node "$JS" get "$j" generated_at)" in '"2020'*) echo "  map still stale"; exit 1;; esac
}

test_structure_put_for_the_mcp_path() {
  home; rm "$KAITO_HOME/.env"
  printf '{"workspace":"acme","me":{"id":"u1","display_name":"kaito"},"boards":{"%s":{"name":"Kaito","identifier":"KAI","states":[{"id":"s1","name":"Done","group":"completed"}],"modules":[],"labels":[],"members":[]}}}' "$T1" | sh "$T" structure put linear >/dev/null || { echo "  put failed"; exit 1; }
  assert_file "$MEM/managers/linear.md"
  grep -q 'Done completed (s1)' "$MEM/managers/linear.md" || { cat "$MEM/managers/linear.md"; exit 1; }
  printf '{"boards":{"%s":{"name":"x","note":"lin_api_abcdefabcdef"}}}' "$T1" | sh "$T" structure put linear >/dev/null 2>&1 && { echo "  secret stored"; exit 1; }
  printf '{"boards":{"%s":{"name":"x","note":"token: abcdefabcdef"}}}' "$T1" | sh "$T" structure put linear >/dev/null 2>&1 && { echo "  secret stored"; exit 1; }
  echo '{"boards":{"../x":{}}}' | sh "$T" structure put linear >/dev/null 2>&1 && { echo "  bad id stored"; exit 1; }
  echo '{"boards":{"KAI":{}}}' | sh "$T" structure put linear >/dev/null 2>&1 && { echo "  team key stored as an id"; exit 1; }
  echo '{}' | sh "$T" structure put plane >/dev/null 2>&1 && { echo "  put for another manager"; exit 1; }
  grep -q lin_api_ "$MEM/managers/linear.json" && { echo "  secret on disk"; exit 1; }
  assert_eq "$(grep -c . "$LOG" | tr -d ' ')" 0 "no network"
}

test_key_never_in_output_or_cache() {
  home; kill $SPID; STUB_AUTH=someotherkey stub
  sh "$T" map "$T1" > "$HOME/out" 2>&1; sh "$T" boards >> "$HOME/out" 2>&1; sh "$T" pull >> "$HOME/out" 2>&1
  grep -q "$LK" "$HOME/out" && { echo "  key in output"; cat "$HOME/out"; exit 1; }
  grep -q "linear 401" "$HOME/out" || { echo "  no 401 shown"; cat "$HOME/out"; exit 1; }
  grep -rq "$LK" "$MEM" 2>/dev/null && { echo "  key in memory"; exit 1; }
  assert_eq "$(last Teams creds)" true "key sent in the header"
}

test_link_attaches_a_url_once() {
  home; sh "$T" map "$T1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  assert_eq "$(sh "$T" link KAI-4 https://github.com/acme/app/pull/12 "PR 12")" "ok KAI-4" link
  assert_eq "$(last AttachmentCreate vars.input.url vars.input.title)" "https://github.com/acme/app/pull/12 PR 12" input
  for u in "javascript:alert(1)" "not a url" "https://user:pw@example.test/x" ""; do
    sh "$T" link KAI-4 "$u" >/dev/null 2>&1 && { echo "  accepted '$u'"; exit 1; }
  done
  assert_eq "$(count AttachmentCreate)" 1 "bad urls never sent"
  assert_eq "$(sh "$T" link KAI-4 https://github.com/acme/app/pull/12)" "ok KAI-4" relink
  assert_eq "$(last AttachmentCreate vars.input.title)" "https://github.com/acme/app/pull/12" "title defaults to the url"
  assert_eq "$(attachments KAI-4)" 1 "linking twice makes one attachment"
}

test_check_refuses_an_item_that_is_not_a_child() {
  home; sh "$T" map "$T1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  out=$(sh "$T" check KAI-1 KAI-5 2>&1) && { echo "  ticked another task's item"; exit 1; }
  has "$out" "KAI-5 is not a sub-item of KAI-1"
  assert_eq "$(count IssueUpdate)" 0 "nothing changed"
}

test_project_mapping_refuses_issues_outside_the_project() {
  home; sh "$T" map "$T1/$PJ" >/dev/null; sh "$T" pull >/dev/null || exit 1
  out=$(sh "$T" done KAI-5 2>&1) && { echo "  closed an issue outside the project"; exit 1; }
  has "$out" "KAI-5 is not in the project"
  assert_eq "$(count IssueUpdate)" 0 "nothing changed"
  # a sub-issue of a project issue is in scope, and so is the issue itself
  sh "$T" done KAI-2 >/dev/null || { echo "  refused a sub-issue of a project issue"; exit 1; }
  sh "$T" comment KAI-4 "Merged" >/dev/null || { echo "  refused a project issue"; exit 1; }
  out=$(sh "$T" done PER-1 2>&1) && { echo "  wrote to another team"; exit 1; }
  has "$out" "PER-1 is in another team"
  assert_eq "$(count IssueUpdate)" 1 "only KAI-2 changed"
}

test_open_sub_item_of_a_closed_parent_is_listed() {
  home; sh "$T" map "$T1" >/dev/null || exit 1
  sh "$T" item add KAI-6 "Follow up" >/dev/null || { echo "  item add failed"; exit 1; }
  sh "$T" pull >/dev/null || exit 1
  has "$(sh "$T" list)" "KAI-8 To Do Follow up"
}

test_new_issues_and_sub_issues_default_to_the_key_owner() {
  # no discover has run, so the owner is asked from Linear
  home; sh "$T" map "$T1" >/dev/null || exit 1
  sh "$T" add "Ship the provider" >/dev/null || exit 1
  assert_eq "$(last IssueCreate vars.input.assigneeId)" "$ME" "issue assigned to me"
  assert_eq "$(last IssueCreate vars.input.projectId)" undefined "no project on a team mapping"
  sh "$T" item add KAI-8 "Write the docs" >/dev/null || exit 1
  assert_eq "$(last IssueCreate vars.input.assigneeId)" "$ME" "sub-issue assigned to me"
}

test_rate_limited_read_waits_as_told_and_succeeds() {
  home; kill $SPID; STUB_FAIL="States 429 1;Issues 429 1" stub
  sh "$T" map "$T1" >/dev/null || exit 1
  assert_eq "$(sh "$T" pull)" "pulled 3 issues" "retried after the wait Linear asked for"
  assert_eq "$(count Issues)" 2 "one retry"
}

test_tracking_never_refuses_reads_and_writes() {
  home; sh "$T" map "$T1" >/dev/null || exit 1
  sh "$T" tracker set linear tracking=never >/dev/null || exit 1
  : > "$LOG"
  has "$(sh "$T" pull)" "tracking is off"
  sh "$T" add "Nope" >/dev/null 2>&1 && { echo "  wrote with tracking off"; exit 1; }
  sh "$T" done KAI-4 >/dev/null 2>&1 && { echo "  wrote with tracking off"; exit 1; }
  assert_eq "$(grep -c . "$LOG" | tr -d ' ')" 0 "no requests"
}

test_tracker_flag_adds_linear_next_to_plane() {
  home plane
  sh "$T" tracker add plane "$T2" Work >/dev/null || exit 1   # an existing Plane tracker; its id is never read here
  out=$(sh "$T" --tracker linear status) || { echo "  status refused: $out"; exit 1; }
  printf "%s\n" "$out" | grep -qx "manager: linear" || { echo "$out"; exit 1; }
  printf "%s\n" "$out" | grep -q "^credentials: yes" || { echo "$out"; exit 1; }
  has "$(sh "$T" --tracker linear boards)" "$T1 KAI Kaito"
  has "$(sh "$T" --tracker linear projects "$T1")" "$T1/$PJ Kaito Skills"
  out=$(sh "$T" --tracker linear add "Too soon" 2>&1) && { echo "  add without a linear tracker"; exit 1; }
  has "$out" "no linear tracker"
  sh "$T" --tracker linear map "$T1/$PJ" >/dev/null || { echo "  map failed"; exit 1; }
  grep -qx "tracker: plane $T2 Work | role=official | tracking=ask" "$PF" || { cat "$PF"; exit 1; }
  grep -q "^tracker: linear $T1/$PJ Kaito / Kaito Skills | " "$PF" || { cat "$PF"; exit 1; }
  assert_eq "$(sh "$T" --tracker linear pull)" "pulled 2 issues" "the new tracker works"
  assert_eq "$(count IssueCreate)" 0 "nothing written"
}

test_tracker_flag_keeps_an_old_plane_board_line() {
  home plane
  mkdir -p "$MEM/projects"; printf 'board: plane %s Work\n' "$T2" > "$PF"
  sh "$T" --tracker linear map "$T1" >/dev/null || { echo "  map failed"; exit 1; }
  grep -q "^tracker: plane $T2 Work" "$PF" || { echo "  plane board lost"; cat "$PF"; exit 1; }
  grep -q "^tracker: linear $T1 Kaito" "$PF" || { cat "$PF"; exit 1; }
}

test_tracker_flag_on_a_machine_with_no_manager() {
  home none
  assert_eq "$(sh "$T" status | head -n1)" "manager: none" "no manager"
  out=$(sh "$T" --tracker linear status) || exit 1
  printf "%s\n" "$out" | grep -qx "manager: linear" || { echo "$out"; exit 1; }
  printf "%s\n" "$out" | grep -qx "board: none" || { echo "$out"; exit 1; }
  sh "$T" --tracker linear add "Too soon" >/dev/null 2>&1 && { echo "  add without a linear tracker"; exit 1; }
  assert_eq "$(sh "$T" --tracker linear map "$T1")" "board: linear $T1 Kaito" map
  printf "%s\n" "$(sh "$T" status)" | grep -qx "manager: linear" || { echo "  project does not use linear"; exit 1; }
  assert_eq "$(sh "$T" pull)" "pulled 3 issues" pull
}

# Send input after the terminal disables echo and prints the prompt.
linear_login() {
  printf '%s\n' "$1" | python3 "$TESTS_DIR/fixtures/pty-answer.py" 'Linear API key: ' sh "$T" login > "$HOME/o" 2>&1
}

test_login_checks_and_saves_the_key() {
  home; printf 'OTHER=1\nexport LINEAR_API_KEY=old\n' > "$KAITO_HOME/.env"
  linear_login "$LK" || { cat "$HOME/o"; exit 1; }
  has "$(cat "$HOME/o")" "saved Linear credentials for kaito to $KAITO_HOME/.env"
  grep -q "$LK" "$HOME/o" && { echo "  key echoed"; exit 1; }
  assert_eq "$(cat "$KAITO_HOME/.env")" "OTHER=1
LINEAR_API_KEY=$LK" "other lines kept, old key replaced"
  assert_eq "$(ls -l "$KAITO_HOME/.env" | cut -c1-10)" "-rw-------" "mode 600"
  assert_eq "$(cfg_get tasks.steps.credentials)" true step
  assert_eq "$(last Viewer creds)" true "checked live"
  kill $SPID; STUB_AUTH=someotherkey stub
  linear_login lin_api_WRONG
  has "$(cat "$HOME/o")" "Linear did not accept that key; nothing saved"
  linear_login 'bad key!'
  has "$(cat "$HOME/o")" "does not look like a Linear API key"
  assert_eq "$(sed -n 2p "$KAITO_HOME/.env")" "LINEAR_API_KEY=$LK" "a failed login keeps the saved key"
}

test_key_from_config_linear_env() {
  home; rm "$KAITO_HOME/.env"; mkdir -p "$HOME/.config/linear"
  printf 'export LINEAR_API_KEY="%s"\n' "$LK" > "$HOME/.config/linear/.env"
  out=$(sh "$T" status 2>&1)
  printf "%s\n" "$out" | grep -qx "credentials: yes ($HOME/.config/linear/.env)" || { echo "$out"; exit 1; }
  case "$out" in *"$LK"*) echo "  leaked"; exit 1;; esac
  has "$(sh "$T" boards)" "$T1 KAI Kaito"
  printf 'LINEAR_API_KEY=%s\n' "$LK" > "$KAITO_HOME/.env"
  printf "%s\n" "$(sh "$T" status)" | grep -qx "credentials: yes ($KAITO_HOME/.env)" || { echo "  ~/.kaito/.env should come first"; exit 1; }
}

test_failed_refresh_after_a_write_still_reports_remote_ok() {
  home; sh "$T" map "$T1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  # a lock that cannot be taken over (a file, not a dir) makes the local step die after its wait
  L="$MEM/tasks/.$sl.lock"; rm -rf "$L"; : > "$L"
  out=$(sh "$T" add "Once only" 2>"$HOME/err") || { echo "  exit 1 after a remote write"; cat "$HOME/err"; exit 1; }
  assert_eq "$out" "remote ok (KAI-8), local refresh failed: run pull" msg
  assert_eq "$(count IssueCreate)" 1 "created once"
}

test_unreachable_team_never_blocks_a_pull() {
  T9=99999999-9999-4999-8999-999999999999
  home; sh "$T" map "$T1" >/dev/null; sh "$T" consent yes "$T1" >/dev/null; sh "$T" discover >/dev/null || exit 1
  sh "$T" consent yes "$T1" "$T9" >/dev/null || exit 1
  j="$MEM/managers/linear.json"
  node -e 'const fs=require("fs"),[f,t]=process.argv.slice(1);const m=JSON.parse(fs.readFileSync(f));m.boards[t]={name:"Gone",identifier:"GON",states:[]};m.generated_at="2020-01-01T00:00:00.000Z";fs.writeFileSync(f,JSON.stringify(m))' "$j" "$T9"
  assert_eq "$(sh "$T" pull 2>"$HOME/err")" "pulled 3 issues" "pull goes on"
  has "$(cat "$HOME/err")" "could not refresh the board structure"
  out=$(sh "$T" map "$T9" 2>&1) && { echo "  mapped a missing team"; exit 1; }
  assert_eq "$out" "kaito-tasks: no team $T9 in this workspace" "map message"
  out=$(sh "$T" projects "$T9" 2>&1) && { echo "  listed a missing team"; exit 1; }
  assert_eq "$out" "kaito-tasks: no team $T9 in this workspace" "projects message"
}

test_tracking_never_holds_while_a_new_tracker_is_set_up() {
  home plane; sh "$T" tracking never >/dev/null || exit 1
  sh "$T" --tracker linear consent yes "$T1" >/dev/null || exit 1
  : > "$LOG"
  has "$(sh "$T" --tracker linear discover)" "tracking is off for this project; turn it on with: kaito-tasks.sh tracking ask"
  has "$(sh "$T" --tracker linear map "$T1")" "tracking is off"
  assert_eq "$(grep -c . "$LOG" | tr -d ' ')" 0 "no requests"
  grep -q linear "$PF" && { echo "  mapped anyway"; cat "$PF"; exit 1; }
  assert_no "$MEM/managers/linear.json"
  has "$(sh "$T" --tracker linear boards)" "$T1 KAI Kaito"   # account-level reads still work
  sh "$T" tracking ask >/dev/null; sh "$T" --tracker linear map "$T1" >/dev/null || { echo "  map after tracking ask"; exit 1; }
}

test_sub_issue_of_a_sub_issue_is_listed() {
  home; sh "$T" map "$T1" >/dev/null || exit 1
  sh "$T" item add KAI-2 "Deep one" >/dev/null || exit 1
  assert_eq "$(sh "$T" pull)" "pulled 4 issues" "KAI-8 stands alone"
  has "$(sh "$T" list)" "KAI-8 To Do Deep one"
  grep -q -- 'id:KAI-2 -->' "$CACHE/KAI-1-add-linear-support.md" || { echo "  child lost"; exit 1; }
}

test_team_key_line_goes_to_the_mcp_until_mapped() {
  home plane; mkdir -p "$MEM/projects"
  echo 'tracker: linear KAI Kaito on acme | role=official | tracking=ask' > "$PF"
  assert_eq "$(sh "$T" add "Not here")" "use the linear MCP; see references/tasks.md" default
  assert_eq "$(sh "$T" --tracker linear done KAI-4)" "use the linear MCP; see references/tasks.md" named
  assert_eq "$(grep -c . "$LOG" | tr -d ' ')" 0 "no requests"
  sh "$T" --tracker linear map "$T1" >/dev/null || { echo "  map refused"; exit 1; }
  grep -qx "tracker: linear $T1 Kaito | role=official | tracking=ask" "$PF" || { cat "$PF"; exit 1; }
  assert_eq "$(sh "$T" pull)" "pulled 3 issues" "now scripted"
}

test_remap_drops_the_old_cache() {
  home; sh "$T" map "$T1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  mkdir -p "$CACHE/conflicts"; echo mine > "$CACHE/conflicts/KAI-5-company-admin.conflict.md"
  sh "$T" map "$T1" >/dev/null; assert_file "$CACHE/KAI-5-company-admin.md"   # same id: cache stays
  sh "$T" map "$T1/$PJ" >/dev/null || exit 1
  assert_no "$CACHE/KAI-5-company-admin.md"; assert_no "$CACHE/index.md"
  assert_file "$CACHE/conflicts/KAI-5-company-admin.conflict.md"
  out=$(sh "$T" done KAI-5 2>&1) && { echo "  wrote outside the project"; exit 1; }
  has "$out" "KAI-5 is not in the project"
}

test_remap_from_another_checkout_cannot_write_through_a_stale_cache() {
  home
  for d in a b; do mkdir -p "$HOME/$d"; (cd "$HOME/$d" && git init -q && git remote add origin https://example.com/acme/app.git) || exit 1; done
  sb=$(sh "$REPO/helpmekaito/scripts/kaito-codegraph.sh" slug "$HOME/b"); CB="$MEM/tasks/linear/$sb"
  (cd "$HOME/a" && sh "$T" map "$T1" >/dev/null) || exit 1
  (cd "$HOME/b" && sh "$T" pull >/dev/null) || exit 1
  assert_file "$CB/KAI-5-company-admin.md"
  (cd "$HOME/a" && sh "$T" map "$T1/$PJ" >/dev/null) || exit 1
  assert_file "$CB/KAI-5-company-admin.md"   # B's cache is not touched by A's remap
  n=$(count IssueUpdate)
  out=$(cd "$HOME/b" && sh "$T" done KAI-5 2>&1) && { echo "  wrote outside the project"; exit 1; }
  has "$out" "KAI-5 is not in the project"
  assert_eq "$(count IssueUpdate)" "$n" "no mutation for the out-of-scope issue"
  assert_no "$CB/KAI-5-company-admin.md"
}

test_ratelimited_400_read_retries_and_succeeds() {
  home; kill $SPID; STUB_FAIL="Issues RATELIMITED 1" stub
  sh "$T" map "$T1" >/dev/null || exit 1
  assert_eq "$(sh "$T" pull)" "pulled 3 issues" "a 400 RATELIMITED is retried"
  assert_eq "$(count Issues)" 2 "one retry"
  kill $SPID; STUB_FAIL="IssueCreate RATELIMITED 1" stub
  out=$(sh "$T" add "Once" 2>&1) && { echo "  should fail"; exit 1; }
  has "$out" "linear 429 IssueCreate"; assert_eq "$(count IssueCreate)" 1 "writes never retry"
}
