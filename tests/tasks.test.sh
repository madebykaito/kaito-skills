#!/bin/sh
. "$(dirname "$0")/lib.sh"
T="$REPO/helpmekaito/scripts/kaito-tasks.sh"
TR="$REPO/helpmekaito/scripts/kaito-trello.mjs"
JS="$REPO/helpmekaito/scripts/kaito-json.mjs"
FK=FAKEKEY0123456789
FT=FAKETOKEN9876543210abcdef

# stub: starts the fake Trello, sets LOG, SPID, KAITO_TRELLO_API; stops it when the test exits
stub() {
  LOG="$HOME/log.jsonl"; : > "$LOG"; rm -f "$HOME/port"
  # started from a throwaway shell so its kill prints no job notice
  SPID=$(sh -c 'node "$@" >/dev/null 2>&1 & echo $!' _ "$TESTS_DIR/stubs/trello-api.mjs" "$LOG" "$HOME/port")
  trap 'kill $SPID 2>/dev/null' EXIT
  i=0; while [ ! -s "$HOME/port" ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done
  KAITO_TRELLO_API="http://127.0.0.1:$(cat "$HOME/port")/1"; export KAITO_TRELLO_API
}
# home <manager>: temp home, config, project folder as cwd; trello also gets the stub and fake creds
home() {
  mk_home; mkdir -p "$KAITO_HOME" "$HOME/proj"; cd "$HOME/proj" || exit 1
  printf '{"tasks":{"manager":"%s","state":"pending"}}\n' "$1" > "$KAITO_HOME/config.json"
  if [ "$1" = trello ]; then
    stub; printf 'OBSIDIAN_API_KEY=keepme\nTRELLO_KEY=%s\nTRELLO_TOKEN=%s\n' "$FK" "$FT" > "$KAITO_HOME/.env"
  fi
  MEM="$KAITO_HOME/memory"
}
# count <METHOD> <path>: matching requests in the stub log. The path goes to node JSON-quoted, which
# Git Bash leaves alone (it rewrites a bare /path into a Windows path).
count() { node -e 'const [f,m,q]=process.argv.slice(1);const p=JSON.parse(q);console.log(require("fs").readFileSync(f,"utf8").split("\n").filter(Boolean).map(JSON.parse).filter(e=>e.method===m&&e.path===p).length)' "$LOG" "$1" "\"$2\""; }
reqs() { grep -c . "$LOG" | tr -d ' '; }
# last <METHOD> <path-prefix> <field>...: fields (dot paths) of the last matching request, space separated
last() { _lm=$1 _lp=$2; shift 2; node -e 'const [f,m,q,...ks]=process.argv.slice(1);const p=JSON.parse(q);const e=require("fs").readFileSync(f,"utf8").split("\n").filter(Boolean).map(JSON.parse).filter(e=>e.method===m&&e.path.startsWith(p)).pop();console.log(e?ks.map(k=>{const v=k.split(".").reduce((o,x)=>o?.[x],e);return Array.isArray(v)?v.join():String(v)}).join(" "):"none")' "$LOG" "$_lm" "\"$_lp\"" "$@"; }
# cache: the project's task folder (Trello cache lives under tasks/trello/)
cache() {
  sl=$(sh "$REPO/helpmekaito/scripts/kaito-codegraph.sh" slug "$HOME/proj")
  if [ "$(node "$JS" get "$KAITO_HOME/config.json" tasks.manager)" = '"trello"' ]; then echo "$MEM/tasks/trello/$sl"; else echo "$MEM/tasks/$sl"; fi
}
mapped() { sh "$T" map b1 >/dev/null || { echo "  map failed"; exit 1; }; }
# c1 <field>: a field of the seeded "[HI] Fix login" card, read straight from the stub
c1() { KAITO_TRELLO_KEY=$FK KAITO_TRELLO_TOKEN=$FT node "$TR" GET /boards/b1/cards/all | node -pe 'JSON.parse(require("fs").readFileSync(0)).find(c=>c.name.includes("Fix login"))[process.argv[1]]' "$1"; }

test_wrapper_retries_get_once_on_429() {
  home trello; export KAITO_TRELLO_KEY=$FK KAITO_TRELLO_TOKEN=$FT
  kill $SPID; STUB_FAIL="GET /members/me 429 1" stub
  out=$(node "$TR" GET /members/me) || { echo "  GET failed: $out"; exit 1; }
  assert_eq "$(count GET /members/me)" 2 "one retry"
  kill $SPID; STUB_FAIL="GET /members/me 500 5" stub
  out=$(node "$TR" GET /members/me 2>&1) && { echo "  should fail"; exit 1; }
  assert_eq "$out" "trello 500 GET /members/me" msg
  assert_eq "$(count GET /members/me)" 2 "only one retry"
}

test_wrapper_never_retries_post() {
  home trello; export KAITO_TRELLO_KEY=$FK KAITO_TRELLO_TOKEN=$FT
  kill $SPID; STUB_FAIL="POST /cards 429 1" stub
  out=$(node "$TR" POST /cards '{"idList":"l1","name":"x"}' 2>&1) && { echo "  should fail"; exit 1; }
  assert_eq "$out" "trello 429 POST /cards" msg
  assert_eq "$(count POST /cards)" 1 "no retry"
}

test_wrapper_needs_env_creds() {
  home trello
  node "$TR" GET /members/me >/dev/null 2>&1 && { echo "  should fail"; exit 1; }
  assert_eq "$(reqs)" 0 "no request without creds"
}

test_other_manager_points_at_mcp() {
  home asana
  out=$(sh "$T" list); rc=$?
  assert_eq "$rc" 0 rc
  assert_eq "$out" "use the asana MCP; see references/tasks.md" msg
}

test_status_never_prints_values() {
  home trello; mapped
  out=$(sh "$T" status 2>&1)
  case "$out" in *"$FT"*|*"$FK"*) echo "  leaked"; exit 1;; esac
  printf "%s\n" "$out" | grep -qx "manager: trello" || { echo "$out"; exit 1; }
  printf "%s\n" "$out" | grep -q "^credentials: yes" || { echo "$out"; exit 1; }
  printf "%s\n" "$out" | grep -qx "board: trello b1 Work" || { echo "$out"; exit 1; }
  printf "%s\n" "$out" | grep -qx "discovery: not asked" || { echo "$out"; exit 1; }
  printf "%s\n" "$out" | grep -qx "onboarding: pending" || { echo "$out"; exit 1; }
}

test_login_refuses_without_tty() {
  home trello
  out=$(sh "$T" login < /dev/null 2>&1) && { echo "  should refuse"; exit 1; }
  case "$out" in *"in a terminal"*) ;; *) echo "$out"; exit 1;; esac
  assert_eq "$(reqs)" 0 "no request"
}

test_login_stores_creds_and_keeps_other_lines() {
  home trello; printf 'OBSIDIAN_API_KEY=keepme\nTRELLO_KEY=old\n' > "$KAITO_HOME/.env"
  command -v script >/dev/null || return 0
  # type only once the key prompt shows (echo is off by then), as a person would; give up after 30s
  : > "$HOME/out"
  # BSD script (macOS) takes the command as args; util-linux script (Linux) takes it with -c
  pty() { if script --version 2>/dev/null | grep -q util-linux; then script -q -e -c "sh '$T' login" /dev/null
          else script -q /dev/null sh "$T" login; fi; }
  out=$( { i=0; until grep -q "Trello API key:" "$HOME/out" || [ $i -ge 300 ]; do sleep 0.1; i=$((i+1)); done
           printf '%s\n%s\n' "$FK" "$FT"; sleep 3; } | pty 2>&1 | tee "$HOME/out")
  case "$out" in *"$FT"*) echo "  token echoed"; exit 1;; esac
  grep -qx "OBSIDIAN_API_KEY=keepme" "$KAITO_HOME/.env" || { echo "  lost other line"; exit 1; }
  grep -qx "TRELLO_TOKEN=$FT" "$KAITO_HOME/.env" || { echo "$out"; exit 1; }
  assert_eq "$(grep -c '^TRELLO_KEY=' "$KAITO_HOME/.env" | tr -d ' ')" 1 "one key line"
  assert_eq "$(ls -l "$KAITO_HOME/.env" | cut -c1-10)" "-rw-------" mode
  assert_eq "$(node "$JS" get "$KAITO_HOME/config.json" tasks.steps.credentials)" true step
  assert_eq "$(count GET /members/me)" 1 validated
}

test_credential_precedence_and_no_mixing() {
  home trello
  printf 'TRELLO_KEY=homekey\nTRELLO_TOKEN=hometok\n' > "$KAITO_HOME/.env"
  mkdir -p "$HOME/.config/trello"; printf 'TRELLO_KEY=cfgkey\nTRELLO_TOKEN="cfgtok"\n' > "$HOME/.config/trello/.env"
  # env pair first
  kill $SPID; STUB_AUTH="envkey:envtok" stub
  TRELLO_KEY=envkey TRELLO_TOKEN=envtok sh "$T" boards >/dev/null || { echo "  env pair not used"; exit 1; }
  # then ~/.kaito/.env, even when env has only a key
  kill $SPID; STUB_AUTH="homekey:hometok" stub
  TRELLO_KEY=envkey sh "$T" boards >/dev/null || { echo "  kaito .env pair not used"; exit 1; }
  # then ~/.config/trello/.env (quotes stripped)
  rm "$KAITO_HOME/.env"; kill $SPID; STUB_AUTH="cfgkey:cfgtok" stub
  sh "$T" boards >/dev/null || { echo "  trello .env pair not used"; exit 1; }
  # key in one place, token in another: never mixed
  printf 'TRELLO_TOKEN=lonetok\n' > "$KAITO_HOME/.env"; rm "$HOME/.config/trello/.env"
  out=$(TRELLO_KEY=envkey sh "$T" boards 2>&1) && { echo "  mixed creds used"; exit 1; }
  case "$out" in *"no Trello credentials"*) ;; *) echo "$out"; exit 1;; esac
  assert_eq "$(reqs)" 1 "no request with mixed creds"
  TRELLO_KEY=envkey sh "$T" status | grep -qx "credentials: no" || { echo "  status"; exit 1; }
}

test_discover_refuses_without_consent() {
  home trello
  sh "$T" discover >/dev/null 2>&1 && { echo "  should refuse"; exit 1; }
  sh "$T" consent no b1 >/dev/null
  sh "$T" discover >/dev/null 2>&1 && { echo "  should refuse after no"; exit 1; }
  assert_eq "$(reqs)" 0 "no request"
  assert_no "$MEM/managers"
  assert_eq "$(node "$JS" get "$KAITO_HOME/config.json" tasks.discovery.consent)" '"no"' consent
}

test_discover_writes_map_without_card_contents() {
  home trello
  sh "$T" consent yes b1 >/dev/null
  sh "$T" discover >/dev/null || { echo "  discover failed"; exit 1; }
  j="$MEM/managers/trello.json"; md="$MEM/managers/trello.md"
  assert_file "$j"; assert_file "$md"
  assert_eq "$(node -pe 'const j=require(process.argv[1]).boards.b1;[j.name,j.lists.map(l=>l.id+"="+l.name).join(","),j.labels[0].id,j.custom_fields[1].options.map(o=>o.id+"="+o.value).join(","),JSON.stringify(j.members)].join("|")' "$j")" \
    'Work|l1=To Do,l2=Doing,l3=Done|lb1|o1=High,o2=Low|[{"id":"m1","username":"kaito"},{"id":"m2","username":"other"}]' map
  assert_eq "$(node -pe 'const s=require(process.argv[1]).boards.b1.card_style;[s.sampled,s.title_pattern,s.checklist_rate,s.due_rate,s.ref_field].join("|")' "$j")" \
    '3|bracket prefix 100%|33%|33%|Ref 33%' style
  assert_eq "$(node -pe 'require(process.argv[1]).me.id' "$j")" m1 me
  head -n1 "$md" | grep -q "generated" || { echo "  md header"; exit 1; }
  grep -q "To Do (l1)" "$md" || { echo "  md ids"; exit 1; }
  grep -q "50 lists" "$md" || { echo "  md caps"; exit 1; }
  if grep -Eq "Fix login|Same title|private words|Other Person" "$j" "$md"; then echo "  card contents stored"; exit 1; fi
  [ -z "$(ls "$MEM/managers" | grep tmp)" ] || { echo "  temp file left"; exit 1; }
  assert_eq "$(count GET /boards/b2/lists)" 0 "unconsented board not fetched"
}

test_discover_partial_failure_keeps_old_map() {
  home trello
  sh "$T" consent yes b1 b2 >/dev/null; sh "$T" discover >/dev/null
  cp "$MEM/managers/trello.json" "$HOME/j"; cp "$MEM/managers/trello.md" "$HOME/md"
  kill $SPID; STUB_FAIL="GET /boards/b2/labels 500 5" stub
  out=$(sh "$T" discover 2>&1) && { echo "  should fail"; exit 1; }
  case "$out" in *"trello 500 GET /boards/b2/labels"*) ;; *) echo "$out"; exit 1;; esac
  case "$out" in *"$FT"*|*"$FK"*) echo "  leaked"; exit 1;; esac
  cmp -s "$HOME/j" "$MEM/managers/trello.json" || { echo "  json changed"; exit 1; }
  cmp -s "$HOME/md" "$MEM/managers/trello.md" || { echo "  md changed"; exit 1; }
}

test_map_writes_board_line_and_index() {
  home trello
  sh "$T" map b1 >/dev/null
  pf=$(ls "$MEM"/projects/*.md)
  grep -qx "board: trello b1 Work" "$pf" || { cat "$pf"; exit 1; }
  grep -q "^- projects/.*proj$" "$MEM/MEMORY.md" || { cat "$MEM/MEMORY.md"; exit 1; }
  sh "$T" map b2 >/dev/null
  assert_eq "$(grep -c '^board:' "$pf" | tr -d ' ')" 1 "one board line"
  grep -qx "board: trello b2 Home" "$pf" || { cat "$pf"; exit 1; }
  assert_eq "$(grep -c projects/ "$MEM/MEMORY.md" | tr -d ' ')" 1 "one index line"
}

test_pull_builds_cache_with_distinct_files() {
  home trello; mapped
  sh "$T" pull >/dev/null || { echo "  pull failed"; exit 1; }
  d=$(cache)
  assert_file "$d/index.md"
  assert_eq "$(ls "$d" | grep -c 'same-title' | tr -d ' ')" 2 "duplicate titles, two files"
  assert_eq "$(ls "$d" | grep -v index.md | grep -c '\.md$' | tr -d ' ')" 3 "three open cards on b1"
  f=$(ls "$d"/*fix-login.md)
  grep -qx 'title: "\[HI\] Fix login"' "$f" || { cat "$f"; exit 1; }
  grep -qx 'list: "To Do"' "$f" || { cat "$f"; exit 1; }
  grep -qx 'labels: "bug"' "$f" || { cat "$f"; exit 1; }
  grep -qx 'generated: "edit through helpmekaito"' "$f" || { cat "$f"; exit 1; }
  grep -q '^synced_at: "20' "$f" || { cat "$f"; exit 1; }
  grep -q '^### Steps <!-- id:' "$f" || { cat "$f"; exit 1; }
  grep -q '^- \[ \] write test <!-- id:' "$f" || { cat "$f"; exit 1; }
  grep -q 'private words alpha' "$f" || { cat "$f"; exit 1; }
  out=$(sh "$T" list)
  assert_eq "$(printf "%s\n" "$out" | wc -l | tr -d ' ')" 3 "list lines"
  printf "%s\n" "$out" | grep -q "To Do.*\[HI\] Fix login.*2 open" || { echo "$out"; exit 1; }
}

test_pull_partial_failure_keeps_cache() {
  home trello; mapped; sh "$T" pull >/dev/null
  d=$(cache); cat "$d"/*.md > "$HOME/before.txt"
  kill $SPID; STUB_FAIL="GET /boards/b1/cards 500 5" stub
  sh "$T" pull >/dev/null 2>&1 && { echo "  should fail"; exit 1; }
  cat "$d"/*.md > "$HOME/after.txt"
  cmp -s "$HOME/before.txt" "$HOME/after.txt" || { echo "  cache changed"; exit 1; }
  [ -z "$(ls -a "$MEM/tasks" | grep new)" ] || { echo "  temp dir left"; exit 1; }
}

test_local_edit_gives_conflict_copy() {
  home trello; mapped; sh "$T" pull >/dev/null
  d=$(cache); f=$(ls "$d"/*fix-login.md); b=$(basename "$f" .md)
  echo "my local note" >> "$f"; touch -t 203001010000 "$f"
  out=$(sh "$T" pull 2>&1) || { echo "$out"; exit 1; }
  case "$out" in *warning*"$b"*) ;; *) echo "$out"; exit 1;; esac
  grep -q "my local note" "$d/conflicts/$b.conflict.md" || { ls -R "$d"; exit 1; }
  grep -q "my local note" "$f" && { echo "  edit not replaced"; exit 1; }
  sh "$T" pull >/dev/null
  assert_file "$d/conflicts/$b.conflict.md"
}

test_archived_card_leaves_cache() {
  home trello; mapped; sh "$T" pull >/dev/null
  d=$(cache); assert_file "$(ls "$d"/*fix-login.md)"
  KAITO_TRELLO_KEY=$FK KAITO_TRELLO_TOKEN=$FT node "$TR" PUT "/cards/$(c1 id)" '{"closed":true}' >/dev/null
  sh "$T" pull >/dev/null
  [ -z "$(ls "$d" | grep fix-login)" ] || { echo "  archived card still cached"; exit 1; }
}

test_trello_item_ops_use_ids() {
  home trello; mapped; sh "$T" pull >/dev/null
  sl=$(c1 shortLink); id=$(c1 id)
  ci=$(KAITO_TRELLO_KEY=$FK KAITO_TRELLO_TOKEN=$FT node "$TR" GET "/cards/$id/checklists" | node -pe 'JSON.parse(require("fs").readFileSync(0))[0].checkItems[0].id')
  sh "$T" check "$(printf %s "$sl" | cut -c1-3)" "$ci" >/dev/null || { echo "  check failed"; exit 1; }
  assert_eq "$(last PUT /cards/ path body.state)" "/cards/$id/checkItem/$ci complete" put
  grep -q "^- \[x\] write test <!-- id:$ci -->" "$(cache)"/*fix-login.md || { cat "$(cache)"/*fix-login.md; exit 1; }
  sh "$T" uncheck "$sl" "$ci" >/dev/null
  assert_eq "$(last PUT /cards/ body.state)" incomplete uncheck
  out=$(sh "$T" item add "$sl" "third step") || { echo "$out"; exit 1; }
  assert_eq "$(last POST /checklists/ body.name)" "third step" itemadd
  grep -q "^- \[ \] third step <!-- id:" "$(cache)"/*fix-login.md || { echo "  item not cached"; exit 1; }
  # a card with no checklist gets one first
  other=$(ls "$(cache)" | grep same-title | head -n1 | cut -d- -f1)
  sh "$T" item add "$other" "first" >/dev/null || { echo "  item add on bare card failed"; exit 1; }
  case "$(last POST /cards/ path)" in */checklists) ;; *) echo "  no checklist made"; exit 1;; esac
  sh "$T" comment "$sl" "done soon" >/dev/null
  assert_eq "$(last POST /cards/ path body.text)" "/cards/$id/actions/comments done soon" comment
  sh "$T" rename "$sl" "Fix login properly" >/dev/null
  [ -n "$(ls "$(cache)" | grep fix-login-properly)" ] || { ls "$(cache)"; exit 1; }
  assert_eq "$(ls "$(cache)" | grep -c "^$sl" | tr -d ' ')" 1 "old file replaced"
  sh "$T" move "$sl" doing >/dev/null
  assert_eq "$(last PUT /cards/ body.idList)" l2 move
  out=$(sh "$T" check S x 2>&1) && { echo "  ambiguous prefix accepted"; exit 1; }
  case "$out" in *ambiguous*) ;; *) echo "$out"; exit 1;; esac
}

test_remote_ok_local_refresh_fail_no_retry() {
  home trello; mapped; sh "$T" pull >/dev/null
  sl=$(c1 shortLink)
  kill $SPID; STUB_FAIL="GET /cards/ 500 9" stub
  out=$(sh "$T" rename "$sl" "New name"); rc=$?
  assert_eq "$rc" 0 rc
  assert_eq "$out" "remote ok ($sl), local refresh failed: run pull" msg
  assert_eq "$(last PUT /cards/ body.name)" "New name" put
  assert_eq "$(grep -c '"method":"PUT"' "$LOG" | tr -d ' ')" 1 "one write"
  kill $SPID; STUB_FAIL="GET /cards/ 500 9" stub
  out=$(sh "$T" add "Brand new"); rc=$?
  assert_eq "$rc" 0 "add rc"
  case "$out" in "remote ok ("*"), local refresh failed: run pull") ;; *) echo "$out"; exit 1;; esac
  assert_eq "$(count POST /cards)" 1 "one create"
}

test_trello_add_defaults_and_assigns_me() {
  home trello; mapped
  sh "$T" consent yes b1 >/dev/null; sh "$T" discover >/dev/null
  out=$(sh "$T" add "New card" --due 2026-12-24T10:00:00Z --desc "why") || { echo "$out"; exit 1; }
  assert_eq "$(last POST /cards body.idList body.idMembers body.due body.desc)" "l1 m1 2026-12-24T10:00:00Z why" post
  [ -n "$(ls "$(cache)" | grep new-card)" ] || { echo "  new card not cached"; exit 1; }
  sh "$T" add "Other" --list doing >/dev/null
  assert_eq "$(last POST /cards body.idList)" l2 "list by name"
  sh "$T" add "Bad" --list nope >/dev/null 2>&1 && { echo "  unknown list accepted"; exit 1; }
  :
}

test_trello_done_and_reopen() {
  home trello; mapped; sh "$T" pull >/dev/null
  sl=$(c1 shortLink)
  sh "$T" done "$sl" >/dev/null
  assert_eq "$(last PUT /cards/ body.idList)" l3 "done list"
  sh "$T" list | grep -q "Fix login" && { echo "  done card listed"; exit 1; }
  sh "$T" reopen "$sl" >/dev/null
  assert_eq "$(last PUT /cards/ body.idList body.closed)" "l1 false" reopen
  # no Done list: done archives, reopen unarchives
  kill $SPID; STUB_NODONE=1 stub; sh "$T" pull >/dev/null
  sl=$(c1 shortLink)
  sh "$T" done "$sl" >/dev/null
  assert_eq "$(last PUT /cards/ body.closed)" true closed
  [ -z "$(ls "$(cache)" | grep fix-login)" ] || { echo "  closed card cached"; exit 1; }
  sh "$T" reopen "$sl" >/dev/null
  assert_eq "$(last PUT /cards/ body.closed)" false unarchive
  [ -n "$(ls "$(cache)" | grep fix-login)" ] || { echo "  reopened card not cached"; exit 1; }
}

test_no_secret_in_output_or_argv() {
  home trello; kill $SPID; STUB_PS=1 stub
  all=$( {
    sh "$T" status; sh "$T" boards; sh "$T" consent yes b1; sh "$T" discover; sh "$T" map b1; sh "$T" pull
    sh "$T" add "Leak check"; sh "$T" list; sh -x "$T" boards
    sh "$T" move nosuchcard12 nolist; sh "$T" item add zzzzzzzz x; sh "$T" map nope
  } 2>&1 )
  case "$all" in *"$FT"*|*"$FK"*) echo "  secret printed"; exit 1;; esac
  cat "$MEM"/managers/* "$MEM"/projects/* "$(cache)"/*.md > "$HOME/files"
  grep -q "$FT" "$HOME/files" && { echo "  secret written to memory"; exit 1; }
  [ "$(reqs)" -gt 10 ] || { echo "  too few requests: $(reqs)"; exit 1; }
  assert_eq "$(grep -c '"creds":true' "$LOG" | tr -d ' ')" "$(reqs)" "creds arrived on every request"
  assert_eq "$(grep -c '"ps_leak":true' "$LOG" | tr -d ' ')" 0 "token never in argv"
  grep -q "$FT" "$LOG" && { echo "  token reached the query log"; exit 1; }
  :
}

test_obsidian_add_items_done_reopen() {
  home obsidian
  out=$(sh "$T" add "Write the docs" --due 2026-12-01 --desc "Plain words.") || { echo "$out"; exit 1; }
  id=$(printf %s "$out" | awk '{print $2}')
  case "$id" in t-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-????) ;; *) echo "  bad id $id"; exit 1;; esac
  d=$(cache); f="$d/$id-write-the-docs.md"
  assert_file "$f"
  grep -qx 'status: "todo"' "$f" || { cat "$f"; exit 1; }
  grep -qx 'due: "2026-12-01"' "$f" || { cat "$f"; exit 1; }
  out=$(sh "$T" item add "$id" "first step") || { echo "$out"; exit 1; }
  it=$(sed -n 's/^- \[ \] first step <!-- id:\(i-[a-z0-9]*\) -->$/\1/p' "$f")
  [ -n "$it" ] || { cat "$f"; exit 1; }
  sh "$T" check "$(printf %s "$id" | cut -c1-12)" "$it" >/dev/null
  grep -q "^- \[x\] first step <!-- id:$it -->" "$f" || { cat "$f"; exit 1; }
  sh "$T" comment "$id" "note this" >/dev/null; grep -q "note this" "$f" || { cat "$f"; exit 1; }
  sh "$T" move "$id" doing >/dev/null; grep -qx 'status: "doing"' "$f" || { cat "$f"; exit 1; }
  sh "$T" list | grep -q "$id doing Write the docs (0 open)" || { sh "$T" list; exit 1; }
  grep -q "\[\[$id-write-the-docs\]\]" "$d/index.md" || { cat "$d/index.md"; exit 1; }
  sh "$T" done "$id" >/dev/null
  assert_no "$f"; assert_file "$d/archive/$id-write-the-docs.md"
  grep -qx 'status: "done"' "$d/archive/$id-write-the-docs.md" || exit 1
  [ -z "$(sh "$T" list)" ] || { echo "  done task listed"; exit 1; }
  grep -q "$id" "$d/index.md" && { echo "  done task indexed"; exit 1; }
  sh "$T" reopen "$id" >/dev/null
  assert_file "$f"; grep -qx 'status: "todo"' "$f" || exit 1
  sh "$T" rename "$id" 'Say "hi" now' >/dev/null
  f2="$d/$id-say-hi-now.md"; assert_file "$f2"; assert_no "$f"
  grep -qx 'title: "Say \\"hi\\" now"' "$f2" || { cat "$f2"; exit 1; }
  sh "$T" pull >/dev/null; assert_eq "$?" 0 "pull rc"
}

test_obsidian_rejects_traversal_and_bad_input() {
  home obsidian
  sh "$T" add "x" >/dev/null
  sh "$T" check ../x i-1 >/dev/null 2>&1 && { echo "  traversal accepted"; exit 1; }
  sh "$T" check "a/b" i-1 >/dev/null 2>&1 && { echo "  slash accepted"; exit 1; }
  sh "$T" move t- nope >/dev/null 2>&1 && { echo "  bad status accepted"; exit 1; }
  out=$(sh "$T" add "../../etc") || exit 1
  id=$(printf %s "$out" | awk '{print $2}')
  assert_file "$(cache)/$id-etc.md"
}

test_obsidian_concurrent_item_add() {
  home obsidian
  id=$(sh "$T" add "Busy" | awk '{print $2}')
  i=1; while [ $i -le 6 ]; do sh "$T" item add "$id" "step $i" >/dev/null & i=$((i+1)); done; wait
  f=$(ls "$(cache)"/"$id"-*.md)
  assert_eq "$(grep -c '^- \[ \] step [0-9] <!-- id:i-' "$f" | tr -d ' ')" 6 "all items landed"
}

test_trello_pull_keeps_obsidian_notes() {
  home obsidian; id=$(sh "$T" add "Keep me" | awk '{print $2}'); n=$(ls "$(cache)"/"$id"-*.md)
    node "$JS" set "$KAITO_HOME/config.json" tasks.manager '"trello"'
  stub; printf 'TRELLO_KEY=%s\nTRELLO_TOKEN=%s\n' "$FK" "$FT" > "$KAITO_HOME/.env"
  mapped; sh "$T" pull >/dev/null || { echo "  pull failed"; exit 1; }
  assert_file "$n"
  assert_file "$(cache)/index.md"
}

test_refresh_keeps_local_edit() {
  home trello; mapped; sh "$T" pull >/dev/null
  d=$(cache); f=$(ls "$d"/*fix-login.md); b=$(basename "$f" .md)
  echo "my local note" >> "$f"; touch -t 203001010000 "$f"
  sh "$T" comment "$(sed -n 's/^id: "\(.*\)"$/\1/p' "$f")" "hi" >/dev/null 2>&1 || { echo "  comment failed"; exit 1; }
  grep -q "my local note" "$d/conflicts/$b.conflict.md" || { ls -R "$d"; exit 1; }
}

test_consent_yes_marks_step_only_after_discover() {
  home trello
  sh "$T" consent yes b1 >/dev/null
  assert_eq "$(node "$JS" get "$KAITO_HOME/config.json" tasks.steps.discovery 2>/dev/null)" "" "not done before discover"
  kill $SPID; STUB_FAIL="GET /boards/b1 500 9" stub
  sh "$T" discover >/dev/null 2>&1 && { echo "  should fail"; exit 1; }
  assert_eq "$(node "$JS" get "$KAITO_HOME/config.json" tasks.steps.discovery 2>/dev/null)" "" "not done after failed discover"
  kill $SPID; stub
  sh "$T" discover >/dev/null || { echo "  discover failed"; exit 1; }
  assert_eq "$(node "$JS" get "$KAITO_HOME/config.json" tasks.steps.discovery)" true "done after discover"
}

test_board_line_picks_the_manager_per_project() {
  home obsidian; stub
  printf 'TRELLO_KEY=%s\nTRELLO_TOKEN=%s\n' "$FK" "$FT" > "$KAITO_HOME/.env"
  sl=$(sh "$REPO/helpmekaito/scripts/kaito-codegraph.sh" slug "$HOME/proj")
  mkdir -p "$MEM/projects"; echo "board: trello b1 Work" > "$MEM/projects/$sl.md"
  out=$(sh "$T" status)
  printf "%s\n" "$out" | grep -qx "manager: trello" || { echo "$out"; exit 1; }
  sh "$T" pull >/dev/null || { echo "  pull failed"; exit 1; }
  assert_file "$MEM/tasks/trello/$sl/index.md"
  # another project on the same machine has no board line, so it stays on the config default
  mkdir -p "$HOME/other"; cd "$HOME/other" || exit 1
  out=$(sh "$T" status)
  printf "%s\n" "$out" | grep -qx "manager: obsidian" || { echo "$out"; exit 1; }
}

test_link_attaches_a_url_trello_and_obsidian() {
  home trello; mapped; sh "$T" pull >/dev/null || exit 1
  id=$(c1 shortLink)
  assert_eq "$(sh "$T" link "$id" https://github.com/acme/app/pull/12 "PR 12")" "ok $id" link
  assert_eq "$(last POST "/cards/$(c1 id)/attachments" body.url body.name)" "https://github.com/acme/app/pull/12 PR 12" body
  sh "$T" link "$id" "ftp://example.test/x" >/dev/null 2>&1 && { echo "  bad url accepted"; exit 1; }
  home obsidian
  t=$(sh "$T" add "Note task" | awk '{print $2}')
  sh "$T" link "$t" https://example.test/doc "Design [v2]" >/dev/null || { echo "  obsidian link failed"; exit 1; }
  grep -rqx 'Link: \[Design v2\](https://example.test/doc)' "$(cache)" || { cat "$(cache)"/*.md; exit 1; }
}
