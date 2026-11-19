#!/bin/sh
. "$(dirname "$0")/lib.sh"
T="$REPO/helpmekaito/scripts/kaito-tasks.sh"
JS="$REPO/helpmekaito/scripts/kaito-json.mjs"
PK=plane_api_FAKEKEY0123456789
P1=11111111-1111-4111-8111-111111111111
P2=22222222-2222-4222-8222-222222222222
MOD=33333333-3333-4333-8333-333333333333

# stub: starts the fake Plane, sets LOG, SPID, KAITO_PLANE_API; stops it when the test exits
stub() {
  LOG="$HOME/log.jsonl"; : > "$LOG"; rm -f "$HOME/port"
  SPID=$(sh -c 'node "$@" >/dev/null 2>&1 & echo $!' _ "$TESTS_DIR/stubs/plane-api.mjs" "$LOG" "$HOME/port")
  trap 'kill $SPID 2>/dev/null' EXIT
  i=0; while [ ! -s "$HOME/port" ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done
  KAITO_PLANE_API="http://127.0.0.1:$(cat "$HOME/port")/api/v1"; export KAITO_PLANE_API
}
# home: temp home with manager plane, the stub, fake creds, project folder as cwd
home() {
  mk_home; mkdir -p "$KAITO_HOME" "$HOME/proj"; cd "$HOME/proj" || exit 1
  printf '{"tasks":{"manager":"plane","state":"pending"}}\n' > "$KAITO_HOME/config.json"
  stub; printf 'TRELLO_KEY=keepme\nPLANE_API_KEY=%s\nPLANE_WORKSPACE=acme\n' "$PK" > "$KAITO_HOME/.env"
  MEM="$KAITO_HOME/memory"
  sl=$(sh "$REPO/helpmekaito/scripts/kaito-codegraph.sh" slug "$HOME/proj"); CACHE="$MEM/tasks/plane/$sl"
}
count() { node -e 'const [f,m,q]=process.argv.slice(1);const p=JSON.parse(q);console.log(require("fs").readFileSync(f,"utf8").split("\n").filter(Boolean).map(JSON.parse).filter(e=>e.method===m&&e.path.startsWith(p)).length)' "$LOG" "$1" "\"$2\""; }
last() { _lm=$1 _lp=$2; shift 2; node -e 'const [f,m,q,...ks]=process.argv.slice(1);const p=JSON.parse(q);const e=require("fs").readFileSync(f,"utf8").split("\n").filter(Boolean).map(JSON.parse).filter(e=>e.method===m&&e.path.startsWith(p)).pop();console.log(e?ks.map(k=>{const v=k.split(".").reduce((o,x)=>o?.[x],e);return Array.isArray(v)?v.join():String(v)}).join(" "):"none")' "$LOG" "$_lm" "\"$_lp\"" "$@"; }
W="/workspaces/acme/projects/$P1"
has() { case "$1" in *"$2"*) ;; *) echo "  missing '$2' in: $1"; exit 1 ;; esac; }

test_status_never_prints_the_key() {
  home; sh "$T" map "$P1/$MOD" >/dev/null || exit 1
  out=$(sh "$T" status 2>&1)
  case "$out" in *"$PK"*) echo "  leaked"; exit 1;; esac
  printf "%s\n" "$out" | grep -qx "manager: plane" || { echo "$out"; exit 1; }
  printf "%s\n" "$out" | grep -q "^credentials: yes" || { echo "$out"; exit 1; }
  printf "%s\n" "$out" | grep -qx "board: plane $P1/$MOD ALL / Kaito Skills" || { echo "$out"; exit 1; }
}

test_no_key_points_at_login_and_mcp() {
  home; rm "$KAITO_HOME/.env"
  out=$(sh "$T" boards 2>&1) && { echo "  should fail"; exit 1; }
  has "$out" "login"; has "$out" "Plane MCP"
  assert_eq "$(grep -c . "$LOG" | tr -d ' ')" 0 "no request without a key"
}

test_login_refuses_without_tty() {
  home
  out=$(sh "$T" login </dev/null 2>&1) && { echo "  should fail"; exit 1; }
  has "$out" "run it in a terminal"
}

test_key_and_workspace_come_from_one_source() {
  home; printf 'PLANE_API_KEY=%s\n' "$PK" > "$KAITO_HOME/.env"   # no workspace in the file
  PLANE_WORKSPACE=acme sh "$T" boards >/dev/null 2>&1 && { echo "  mixed sources accepted"; exit 1; }
  out=$(PLANE_API_KEY=$PK PLANE_WORKSPACE=acme sh "$T" boards) || { echo "  env pair refused"; exit 1; }
  has "$out" "$P1 ALL ALL"
}

test_boards_and_modules_list_by_name() {
  home
  assert_eq "$(sh "$T" boards | wc -l | tr -d ' ')" 2 "two projects"
  assert_eq "$(sh "$T" modules "$P1")" "$P1/$MOD Kaito Skills" modules
}

test_map_rejects_bad_ids() {
  home
  for b in "" "a b" "$P1/$MOD/x" "/$MOD" "$P1/" '$(id)'; do
    sh "$T" map "$b" >/dev/null 2>&1 && { echo "  accepted '$b'"; exit 1; }
  done
  :
}

test_pull_whole_project_groups_children() {
  home; sh "$T" map "$P1" >/dev/null || exit 1
  out=$(sh "$T" pull) || { echo "  pull failed"; exit 1; }
  assert_eq "$out" "pulled 3 work items" count   # ALL-1, ALL-4, ALL-5: children and the closed one are not files
  f="$CACHE/ALL-1-add-plane-support.md"; assert_file "$f"
  grep -q '^list: "To Do"$' "$f" || { cat "$f"; exit 1; }
  grep -q '^due: "2026-12-01"$' "$f" || { cat "$f"; exit 1; }
  grep -q '^labels: "bug"$' "$f" && { echo "  labels need discovery"; exit 1; }
  grep -q -- '- \[ \] Write the client <!-- id:ALL-2 -->' "$f" || { cat "$f"; exit 1; }
  grep -q -- '- \[x\] Write the tests <!-- id:ALL-3 -->' "$f" || { cat "$f"; exit 1; }
  assert_no "$CACHE/ALL-2-write-the-client.md"; assert_no "$CACHE/ALL-6-old-shipped-thing.md"
  out=$(sh "$T" list)
  has "$out" "ALL-1 To Do Add Plane support (1 open)"; has "$out" "ALL-5 To Do Company admin"
}

test_pull_module_scope_and_pagination() {
  home; kill $SPID; STUB_PAGE=2 stub
  sh "$T" map "$P1/$MOD" >/dev/null || exit 1
  assert_eq "$(sh "$T" pull)" "pulled 2 work items" "module holds ALL-1 and ALL-4"
  assert_no "$CACHE/ALL-5-company-admin.md"
  [ "$(count GET "$W/work-items/")" -ge 3 ] || { echo "  no cursor follow"; exit 1; }
}

test_pull_failure_keeps_cache() {
  home; sh "$T" map "$P1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  kill $SPID; STUB_FAIL="GET $W/work-items/ 500 5" stub
  sh "$T" pull >/dev/null 2>&1 && { echo "  should fail"; exit 1; }
  assert_file "$CACHE/ALL-1-add-plane-support.md"
}

test_add_goes_to_todo_and_into_the_module() {
  home; sh "$T" map "$P1/$MOD" >/dev/null; sh "$T" consent yes "$P1" >/dev/null; sh "$T" discover >/dev/null || exit 1
  out=$(sh "$T" add "Ship the provider" --due 2026-12-24 --desc "First line") || { echo "  add failed: $out"; exit 1; }
  assert_eq "$out" "added ALL-7 Ship the provider" msg
  assert_eq "$(last POST "$W/work-items/" body.name body.state body.target_date body.description_html)" "Ship the provider s-todo 2026-12-24 <p>First line</p>" body
  assert_eq "$(last POST "$W/work-items/" body.assignees)" "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" "assigned to me"
  assert_eq "$(count POST "$W/modules/$MOD/module-issues/")" 1 "added to the module"
  assert_file "$CACHE/ALL-7-ship-the-provider.md"
}

test_sub_items_add_check_uncheck() {
  home; sh "$T" map "$P1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  assert_eq "$(sh "$T" item add ALL-1 "Write the docs")" "ok ALL-1" add
  f="$CACHE/ALL-1-add-plane-support.md"
  grep -q -- '- \[ \] Write the docs <!-- id:ALL-7 -->' "$f" || { cat "$f"; exit 1; }
  grep -q -- '- \[x\] Write the tests <!-- id:ALL-3 -->' "$f" || { echo "  lost a sibling"; cat "$f"; exit 1; }
  assert_eq "$(sh "$T" check ALL-1 ALL-2)" "ok ALL-1" check
  assert_eq "$(last PATCH "$W/work-items/" body.state)" "s-done" "child moved to the completed state"
  grep -q -- '- \[x\] Write the client <!-- id:ALL-2 -->' "$f" || { cat "$f"; exit 1; }
  sh "$T" uncheck ALL-1 all-2 >/dev/null || exit 1
  assert_eq "$(last PATCH "$W/work-items/" body.state)" "s-todo" "child back to to-do"
  grep -q -- '- \[ \] Write the client <!-- id:ALL-2 -->' "$f" || { cat "$f"; exit 1; }
}

test_rename_move_comment_done_reopen() {
  home; sh "$T" map "$P1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  sh "$T" rename ALL-4 "Move everything to Plane" >/dev/null || exit 1
  assert_file "$CACHE/ALL-4-move-everything-to-plane.md"; assert_no "$CACHE/ALL-4-migrate-to-plane.md"
  sh "$T" move ALL-4 "to do" >/dev/null || exit 1
  assert_eq "$(last PATCH "$W/work-items/" body.state)" "s-todo" "move by state name"
  sh "$T" comment ALL-4 "Done in <PR 12> & merged" >/dev/null || exit 1
  assert_eq "$(last POST "$W/work-items/" body.comment_html)" "<p>Done in &lt;PR 12&gt; &amp; merged</p>" "comment is escaped HTML"
  sh "$T" done ALL-4 >/dev/null || exit 1
  assert_no "$CACHE/ALL-4-move-everything-to-plane.md"
  assert_eq "$(sh "$T" reopen ALL-4)" "ok ALL-4" "reopen by key, not in cache"
  assert_file "$CACHE/ALL-4-move-everything-to-plane.md"
  sh "$T" move ALL-4 Nowhere >/dev/null 2>&1 && { echo "  unknown state accepted"; exit 1; }
  :
}

test_done_without_completed_state_fails_clearly() {
  home; kill $SPID; STUB_NODONE=1 stub
  sh "$T" map "$P1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  out=$(sh "$T" done ALL-4 2>&1) && { echo "  should fail"; exit 1; }
  has "$out" "no completed state"
  assert_eq "$(count PATCH "$W/work-items/")" 0 "nothing written"
}

test_writes_never_retry_and_remote_ok_is_reported() {
  home; sh "$T" map "$P1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  kill $SPID; STUB_FAIL="POST $W/work-items/ 500 1" stub
  sh "$T" add "Once only" >/dev/null 2>&1 && { echo "  should fail"; exit 1; }
  assert_eq "$(count POST "$W/work-items/")" 1 "no retry on a write"
  kill $SPID; STUB_FAIL="GET $W/work-items/ 500 5" stub
  out=$(sh "$T" comment ALL-4 "note")
  has "$out" "remote ok (ALL-4), local refresh failed: run pull"
}

test_discover_needs_consent_and_stores_no_item_text() {
  home; sh "$T" map "$P1" >/dev/null
  sh "$T" discover >/dev/null 2>&1 && { echo "  discover without consent"; exit 1; }
  sh "$T" consent yes "$P1" >/dev/null && sh "$T" discover >/dev/null || { echo "  discover failed"; exit 1; }
  j="$MEM/managers/plane.json"; assert_file "$j"; assert_file "$MEM/managers/plane.md"
  assert_eq "$(node "$JS" get "$j" "boards.$P1.identifier")" '"ALL"' identifier
  grep -q '"group": "completed"' "$j" || { echo "  no state groups"; exit 1; }
  grep -q 'Kaito Skills' "$j" || { echo "  no modules"; exit 1; }
  grep -q 'private words\|Add Plane support' "$j" "$MEM/managers/plane.md" && { echo "  item text stored"; exit 1; }
  case "$(cat "$j" "$MEM/managers/plane.md")" in *"$PK"*) echo "  key stored"; exit 1;; esac
  sh "$T" pull >/dev/null; grep -q '^labels: "bug"$' "$CACHE/ALL-1-add-plane-support.md" || { echo "  label names not used"; exit 1; }
}

test_unknown_state_refreshes_structure_once() {
  home; sh "$T" map "$P1" >/dev/null; sh "$T" consent yes "$P1" >/dev/null; sh "$T" discover >/dev/null; sh "$T" pull >/dev/null || exit 1
  j="$MEM/managers/plane.json"
  # the stored map loses a state, as if it had been added in Plane after discovery
  node -e 'const fs=require("fs"),[f,p]=process.argv.slice(1);const m=JSON.parse(fs.readFileSync(f));m.boards[p].states=m.boards[p].states.filter(s=>s.name!=="In Progress");fs.writeFileSync(f,JSON.stringify(m))' "$j" "$P1"
  sh "$T" move ALL-5 "In Progress" >/dev/null || { echo "  move failed"; exit 1; }
  assert_eq "$(last PATCH "$W/work-items/" body.state)" "s-doing" state
  grep -q '"In Progress"' "$j" || { echo "  map not updated"; exit 1; }
}

test_stale_structure_refreshes_on_pull() {
  home; sh "$T" map "$P1" >/dev/null; sh "$T" consent yes "$P1" >/dev/null; sh "$T" discover >/dev/null || exit 1
  j="$MEM/managers/plane.json"
  sh "$T" pull >/dev/null; n=$(count GET "$W/labels/")
  assert_eq "$n" 1 "a fresh map is left alone"
  node -e 'const fs=require("fs"),f=process.argv[1];const m=JSON.parse(fs.readFileSync(f));m.generated_at="2020-01-01T00:00:00.000Z";fs.writeFileSync(f,JSON.stringify(m))' "$j"
  sh "$T" pull >/dev/null || { echo "  pull failed"; exit 1; }
  assert_eq "$(count GET "$W/labels/")" 2 "a stale map is rediscovered"
  case "$(node "$JS" get "$j" generated_at)" in '"2020'*) echo "  map still stale"; exit 1;; esac
}

test_structure_put_for_the_mcp_path() {
  home; rm "$KAITO_HOME/.env"
  printf '{"workspace":"acme","me":{"id":"u1","display_name":"kaito"},"boards":{"%s":{"name":"ALL","identifier":"ALL","states":[{"id":"s1","name":"Done","group":"completed"}],"modules":[],"labels":[],"members":[]}}}' "$P1" | sh "$T" structure put plane >/dev/null || { echo "  put failed"; exit 1; }
  assert_file "$MEM/managers/plane.md"
  grep -q 'Done completed (s1)' "$MEM/managers/plane.md" || { cat "$MEM/managers/plane.md"; exit 1; }
  printf '{"boards":{"%s":{"name":"x","note":"token: abcdefabcdef"}}}' "$P1" | sh "$T" structure put plane >/dev/null 2>&1 && { echo "  secret stored"; exit 1; }
  echo '{"boards":{"../x":{}}}' | sh "$T" structure put plane >/dev/null 2>&1 && { echo "  bad id stored"; exit 1; }
  assert_eq "$(grep -c . "$LOG" | tr -d ' ')" 0 "no network"
}

test_key_never_in_output_or_cache() {
  home; kill $SPID; STUB_AUTH=someotherkey stub
  sh "$T" map "$P1" > "$HOME/out" 2>&1; sh "$T" boards >> "$HOME/out" 2>&1; sh "$T" pull >> "$HOME/out" 2>&1
  grep -q "$PK" "$HOME/out" && { echo "  key in output"; cat "$HOME/out"; exit 1; }
  grep -q "plane 401" "$HOME/out" || { echo "  no 401 shown"; cat "$HOME/out"; exit 1; }
  grep -rq "$PK" "$MEM" 2>/dev/null && { echo "  key in memory"; exit 1; }
  :
}

test_plane_and_obsidian_projects_on_one_machine() {
  home; sh "$T" map "$P1" >/dev/null || exit 1
  mkdir -p "$HOME/other"; cd "$HOME/other" || exit 1
  node "$JS" set "$KAITO_HOME/config.json" tasks.manager '"obsidian"'
  out=$(sh "$T" status); printf "%s\n" "$out" | grep -qx "manager: obsidian" || { echo "$out"; exit 1; }
  cd "$HOME/proj" || exit 1
  out=$(sh "$T" status); printf "%s\n" "$out" | grep -qx "manager: plane" || { echo "$out"; exit 1; }
  assert_eq "$(sh "$T" pull)" "pulled 3 work items" "mapped project still on Plane"
}

test_link_attaches_a_url() {
  home; sh "$T" map "$P1" >/dev/null; sh "$T" pull >/dev/null || exit 1
  assert_eq "$(sh "$T" link ALL-4 https://github.com/acme/app/pull/12 "PR 12")" "ok ALL-4" link
  assert_eq "$(last POST "$W/work-items/" body.url body.title)" "https://github.com/acme/app/pull/12 PR 12" body
  for u in "javascript:alert(1)" "not a url" "https://user:pw@example.test/x" ""; do
    sh "$T" link ALL-4 "$u" >/dev/null 2>&1 && { echo "  accepted '$u'"; exit 1; }
  done
  assert_eq "$(count POST "$W/work-items/")" 1 "bad urls never sent"
}
