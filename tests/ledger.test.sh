#!/bin/sh
# Approval ledger, kaito-approve and kaito-today (packages 1.2 and 1.3). Fictional owners only.
. "$(dirname "$0")/lib.sh"
B="$REPO/business/scripts"
L() { node "$B/kaito-ledger.mjs" "$@"; }
A() { node "$B/kaito-approve.mjs" "$@"; }
T() { node "$B/kaito-today.mjs" "$@"; }
# AH: kaito-approve as an agent host runs it after its permission prompt.
AH() { env AI_AGENT=1 node "$B/kaito-approve.mjs" "$@"; }
# sql "<statement>": run SQL on the ledger directly, the way someone tampering would.
sql() { node --no-warnings -e 'const {DatabaseSync}=require("node:sqlite");const d=new DatabaseSync(process.argv[1]);const r=d.prepare(process.argv[2]);const o=/^\s*(select|pragma)/i.test(process.argv[2])?r.all():r.run();if(Array.isArray(o))for(const x of o)console.log(Object.values(x).join("\t"))' "$KAITO_HOME/business/ledger.db" "$1"; }
jget() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let v=JSON.parse(s);for(const k of process.argv[1].split("."))v=v?.[k];console.log(Array.isArray(v)||typeof v==="object"?JSON.stringify(v):v)})' "$1"; }

owners() {
  mkdir -p "$KAITO_HOME/owners/lumen-tea" "$KAITO_HOME/owners/ira-das"
  cat > "$KAITO_HOME/owners/lumen-tea/owner.json" <<'EOF'
{"id":"lumen-tea","name":"Lumen Tea Co.","kind":"company","locale":"en-IN","timezone":"Asia/Kolkata","currency":"INR","gstin":"19ABCDE1234F1Z5","channels":{"instagram":"@lumentea.example"},"cloud_ok":false}
EOF
  cat > "$KAITO_HOME/owners/ira-das/owner.json" <<'EOF'
{"id":"ira-das","name":"Ira Das","kind":"person","locale":"en-IN","currency":"INR","channels":{"instagram":"@iradas.example"},"cloud_ok":false}
EOF
  W="$HOME/work"; mkdir -p "$W"
  printf 'First flush from Darjeeling is here.\r\nOrder by Friday.\r\n' > "$W/caption.txt"
  printf 'PNGFAKE-reel-cover-1' > "$W/cover.png"
  printf 'MP4FAKE-reel-video-1' > "$W/reel.mp4"
}
# prop [propose flags]: propose a lumen-tea Reel; sets REF and DIG.
prop() {
  out=$(L propose --owner lumen-tea --account @lumentea.example --action instagram.reel.publish \
    --text-file "$W/caption.txt" --media "$W/reel.mp4" "$W/cover.png" --disclosure ai "$@") || { echo "$out"; exit 1; }
  REF=$(echo "$out" | sed -n 's/^ref=//p'); DIG=$(echo "$out" | sed -n 's/^digest=//p')
  [ -n "$REF" ] && [ ${#DIG} = 64 ] || { echo "  bad propose output: $out"; exit 1; }
}
ok_approve() { AH "$1" --digest "$2" > "$HOME/approve.out" 2>&1 || { cat "$HOME/approve.out"; exit 1; }; }
state() { L status "$1" | sed -n 's/^state=//p'; }
# expect <code> <cmd...>: run and check the exit code.
expect() {
  want=$1; shift
  "$@" > "$HOME/expect.out" 2>&1; got=$?
  [ "$got" = "$want" ] || { echo "  exit $got, want $want: $*"; cat "$HOME/expect.out"; exit 1; }
}
# pty <input> <cmd...>: run cmd on a pseudo-terminal with input typed in. Returns 2 when there is no script(1).
pty() {
  input=$1; shift
  command -v script >/dev/null 2>&1 || return 2
  # Type only once the prompt is up: script(1) sends end-of-file as soon as its input ends.
  if script --version 2>/dev/null | grep -q util-linux; then
    { sleep 2; printf '%s\n' "$input"; sleep 1; } | script -qec "$*" /dev/null
  else
    { sleep 2; printf '%s\n' "$input"; sleep 1; } | script -q /dev/null "$@"
  fi
}
# Agent hosts set these; the terminal path refuses when any is present.
NOAGENT="env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u AI_AGENT -u CODEX_SANDBOX -u CODEX_THREAD_ID -u CODEX_CI -u CODEX_SANDBOX_NETWORK_DISABLED -u GEMINI_CLI -u OPENCODE -u CURSOR_AGENT -u CURSOR_TRACE_ID -u AIDER_MODEL -u GOOSE_PROVIDER -u AMP_API_KEY"

test_propose_stores_read_only_artifacts() {
  mk_home; owners; prop
  text=$(L status "$REF" | sed -n 's/^text=//p')
  case "$text" in "$KAITO_HOME/business/artifacts/"*) ;; *) echo "  text not in the store: $text"; exit 1 ;; esac
  # Stored text is canonical: CRLF became LF, and it hashes to its own name.
  assert_eq "$(cat "$text")" "$(printf 'First flush from Darjeeling is here.\nOrder by Friday.')" canonical
  assert_eq "$(basename "$text")" "$(node -e 'console.log(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$text")" named-by-hash
  assert_eq "$(basename "$(dirname "$text")")" "$(basename "$text" | cut -c1-2)" fan-out
  for f in $(L status "$REF" | sed -n 's/^\(text\|media\)=//p'); do
    assert_eq "$(ls -l "$f" | cut -c1-10)" "-r--r--r--" "mode of $f"
  done
  assert_eq "$(L status "$REF" | grep -c '^media=')" 2 media-count
  # A store write is never edited in place: the same bytes again reuse the file.
  prop; assert_eq "$(find "$KAITO_HOME/business/artifacts" -type f | wc -l | tr -d ' ')" 3 dedup
  if [ "$(id -u)" != 0 ]; then
    ! (printf x >> "$text") 2>/dev/null || { echo "  stored file was writable"; exit 1; }
  fi
}

test_no_experimental_warning() {
  mk_home; owners
  L migrate > /dev/null 2> "$HOME/err" || exit 1
  assert_eq "$(cat "$HOME/err")" "" stderr
}

test_changed_caption_refused() {
  mk_home; owners; prop; A_REF=$REF A_DIG=$DIG
  ok_approve "$A_REF" "$A_DIG"
  # A second proposal with a changed caption has its own digest and no approval.
  printf 'First flush is here. 50%% off today only!\n' > "$W/caption.txt"; prop
  [ "$DIG" != "$A_DIG" ] || { echo "  changed caption kept the digest"; exit 1; }
  expect 3 L claim "$A_REF" --digest "$DIG"
  grep -q 'digest differs' "$HOME/expect.out" || exit 1
  expect 3 L claim "$REF" --digest "$DIG"
  grep -q 'not approved' "$HOME/expect.out" || exit 1
  # Editing the stored caption of the approved action fails the re-hash at claim.
  text=$(L status "$A_REF" | sed -n 's/^text=//p')
  chmod u+w "$text"; printf 'Swapped caption\n' > "$text"
  expect 3 L claim "$A_REF" --digest "$A_DIG"
  grep -q 'payload changed' "$HOME/expect.out" || exit 1
  assert_eq "$(L status "$A_REF" | sed -n 's/^intact=//p')" no intact
  assert_eq "$(state "$A_REF")" approved still-approved
  assert_eq "$(sql "select count(*) from attempts")" 0 no-attempt
}

test_replaced_media_refused() {
  mk_home; owners; prop; ok_approve "$REF" "$DIG"
  m=$(L status "$REF" | sed -n 's/^media=//p' | head -1)
  rm -f "$m"; printf 'MP4FAKE-a-different-video' > "$m"
  expect 3 L claim "$REF" --digest "$DIG"
  grep -q 'media 1 file changed' "$HOME/expect.out" || exit 1
  rm -f "$m"
  expect 3 L claim "$REF" --digest "$DIG"
  grep -q 'media 1 file is missing' "$HOME/expect.out" || exit 1
}

test_changed_disclosure_account_due_refused() {
  mk_home; owners
  for change in "disclosure = 'none'" "account = '@iradas.example'" "due_at = '2099-12-01T04:30:00Z'" "owner = 'ira-das'" "action = 'instagram.story.publish'"; do
    prop --due 2099-12-30T10:00; ok_approve "$REF" "$DIG"
    # The ledger itself refuses to edit a payload field.
    ! sql "update actions set $change where ref = '$REF'" 2>/dev/null || { echo "  trigger let '$change' through"; exit 1; }
    # Someone who drops the trigger still cannot get it past claim.
    sql "drop trigger actions_payload_fixed"
    sql "update actions set $change where ref = '$REF'"
    expect 3 L claim "$REF" --digest "$DIG"
    grep -q 'no longer matches its digest' "$HOME/expect.out" || { echo "  after $change"; exit 1; }
    rm "$KAITO_HOME/business/ledger.db"*  # fresh ledger, trigger back, for the next change
  done
}

test_two_claims_at_once() {
  mk_home; owners; prop; ok_approve "$REF" "$DIG"
  i=0
  while [ $i -lt 6 ]; do
    ( while [ ! -e "$HOME/go" ]; do :; done
      node "$B/kaito-ledger.mjs" claim "$REF" --digest "$DIG" > "$HOME/c.$i" 2>&1; echo $? > "$HOME/rc.$i" ) &
    i=$((i + 1))
  done
  touch "$HOME/go"; wait
  assert_eq "$(cat "$HOME"/rc.* | grep -c '^0$')" 1 one-winner
  assert_eq "$(cat "$HOME"/rc.* | grep -c '^3$')" 5 losers-exit-3
  assert_eq "$(sql "select count(*) from attempts where ref = '$REF'")" 1 one-attempt
  assert_eq "$(state "$REF")" claimed
}

test_lost_response_goes_to_reconcile() {
  mk_home; owners; prop; ok_approve "$REF" "$DIG"
  n=$(L claim "$REF" --digest "$DIG" | sed -n 's/^attempt=//p'); assert_eq "$n" 1 attempt
  # The publisher sent, the response was lost: it records uncertain and never retries.
  L record "$REF" --attempt 1 --result uncertain > /dev/null
  expect 3 L claim "$REF" --digest "$DIG"
  expect 3 L record "$REF" --attempt 1 --result ok
  L reconcile | grep -q "^$REF	uncertain	lumen-tea" || exit 1
  T --owner lumen-tea --now 2026-11-26T12:00:00+05:30 | grep -q "reconcile.*\[$REF\]" || exit 1
  expect 2 L reconcile "$REF" --sent
  L reconcile "$REF" --sent --remote-id 17890001 > /dev/null
  assert_eq "$(state "$REF")" reconciled
  assert_eq "$(L status "$REF" | sed -n 's/^remote_id=//p')" 17890001 remote-id
  assert_eq "$(L reconcile)" "" empty-after
  expect 3 L claim "$REF" --digest "$DIG"
  expect 3 L reconcile "$REF" --failed
}

test_reconcile_failed_and_stale_claim() {
  mk_home; owners; prop; ok_approve "$REF" "$DIG"
  L claim "$REF" --digest "$DIG" > /dev/null
  # A claim that never reported back is listed once it is stale, and cannot be settled before.
  assert_eq "$(L reconcile)" "" not-yet-stale
  L reconcile --now 2099-01-01T00:00:00Z | grep -q "^$REF	stale-claim" || exit 1
  expect 3 L reconcile "$REF" --failed
  L record "$REF" --attempt 1 --result uncertain > /dev/null
  L reconcile "$REF" --failed --note "not on the profile" > /dev/null
  assert_eq "$(state "$REF")" failed
  expect 3 L claim "$REF" --digest "$DIG"
}

test_claim_after_send_refused() {
  mk_home; owners; prop; ok_approve "$REF" "$DIG"
  out=$(L claim "$REF" --digest "$DIG")
  echo "$out" | grep -q "^text=$KAITO_HOME/business/artifacts/" || exit 1
  assert_eq "$(echo "$out" | grep -c '^media=')" 2 media-paths
  L record "$REF" --attempt 1 --result ok --remote-id 1789 > /dev/null
  assert_eq "$(state "$REF")" sent
  expect 3 L claim "$REF" --digest "$DIG"
  grep -q 'already sent' "$HOME/expect.out" || exit 1
  expect 3 L record "$REF" --attempt 1 --result ok
  expect 4 L record "$REF" --attempt 2 --result ok
  expect 3 L reject "$REF"
  expect 3 AH "$REF" --digest "$DIG"
  # No path back: the state flow refuses sent to approved even in raw SQL.
  ! sql "update actions set state = 'approved' where ref = '$REF'" 2>/dev/null || exit 1
}

test_self_approval_refused() {
  mk_home; owners; prop
  # No terminal and no --digest: an agent's shell.
  expect 3 A "$REF" < /dev/null
  grep -q 'no terminal' "$HOME/expect.out" || exit 1
  printf '%s\n' "$(echo "$DIG" | cut -c1-8)" > "$HOME/yes"
  expect 3 A "$REF" < "$HOME/yes"
  # Never from a file, never a prefix: the full digest on the command line only.
  echo "$DIG" > "$HOME/digest.txt"
  expect 2 AH "$REF" --digest "@$HOME/digest.txt"
  expect 2 AH "$REF" --digest "$(echo "$DIG" | cut -c1-8)"
  # The ledger has no approve command, and raw SQL cannot approve without an approval row.
  expect 2 L approve "$REF"
  ! sql "update actions set state = 'approved' where ref = '$REF'" 2>/dev/null || exit 1
  expect 3 L claim "$REF" --digest "$DIG"
  # A pseudo-terminal inside an agent session is still an agent.
  pty "$(echo "$DIG" | cut -c1-8)" env AI_AGENT=1 node "$B/kaito-approve.mjs" "$REF" > "$HOME/pty.out" 2>&1
  if ! command -v script >/dev/null 2>&1; then echo "skip: no script(1) for the pty case"
  else grep -q 'belongs to an agent session' "$HOME/pty.out" || { echo "  pty under AI_AGENT:"; cat "$HOME/pty.out"; exit 1; }
  fi
  assert_eq "$(state "$REF")" proposed
  assert_eq "$(sql "select count(*) from approvals")" 0 no-approval-row
}

test_digest_path_refused_when_host_would_not_ask() {
  mk_home; owners; prop
  mkdir -p "$HOME/.claude"
  echo '{"permissions":{"allow":["Bash(node:*)"]}}' > "$HOME/.claude/settings.json"
  expect 3 AH "$REF" --digest "$DIG"
  grep -q 'allows "Bash(node:\*)"' "$HOME/expect.out" || exit 1
  echo '{"permissions":{"allow":["Bash(node */business/scripts/*)"]}}' > "$HOME/.claude/settings.json"
  expect 3 AH "$REF" --digest "$DIG"
  echo '{"permissions":{"defaultMode":"bypassPermissions"}}' > "$HOME/.claude/settings.json"
  expect 3 AH "$REF" --digest "$DIG"
  mkdir -p "$W/.claude"; echo '{"permissions":{"allow":["Bash"]}}' > "$W/.claude/settings.local.json"
  echo '{}' > "$HOME/.claude/settings.json"
  ( cd "$W" && expect 3 AH "$REF" --digest "$DIG" ) || exit 1
  assert_eq "$(state "$REF")" proposed
  # A narrow rule for other scripts is fine.
  rm -rf "$W/.claude"
  echo '{"permissions":{"allow":["Bash(git status:*)"]}}' > "$HOME/.claude/settings.json"
  ok_approve "$REF" "$DIG"
  assert_eq "$(state "$REF")" approved
  assert_eq "$(sql "select via from approvals where ref = '$REF'")" prompt via
}

test_wrong_digest_refused() {
  mk_home; owners; prop
  other=$(printf '%064d' 0)
  expect 3 AH "$REF" --digest "$other"
  grep -q 'does not match' "$HOME/expect.out" || exit 1
  upper=$(echo "$DIG" | tr a-f A-F)
  expect 2 AH "$REF" --digest "$upper"
  # The terminal path with a wrong prefix (or, under an agent, any prefix) approves nothing.
  pty "deadbeef" $NOAGENT node "$B/kaito-approve.mjs" "$REF" > "$HOME/pty.out" 2>&1
  rc=$?
  [ $rc = 2 ] && echo "skip: no script(1) for the pty case"
  ! grep -q '^approved' "$HOME/pty.out" || { cat "$HOME/pty.out"; exit 1; }
  assert_eq "$(state "$REF")" proposed
}

test_terminal_approval() {
  mk_home; owners; prop
  pty "$(echo "$DIG" | cut -c1-8)" $NOAGENT node "$B/kaito-approve.mjs" "$REF" > "$HOME/pty.out" 2>&1
  rc=$?
  if [ $rc = 2 ] && ! command -v script >/dev/null 2>&1; then echo "skip: no script(1)"; return 0; fi
  if grep -q 'belongs to an agent session' "$HOME/pty.out"; then echo "skip: tests run inside an agent session"; return 0; fi
  grep -q "^approved ref=$REF" "$HOME/pty.out" || { cat "$HOME/pty.out"; exit 1; }
  # The founder saw the whole payload before typing.
  grep -q 'Order by Friday.' "$HOME/pty.out" || exit 1
  grep -q 'disclosure: ai' "$HOME/pty.out" || exit 1
  assert_eq "$(state "$REF")" approved
  assert_eq "$(sql "select via from approvals where ref = '$REF'")" terminal via
}

test_show_card_is_read_only() {
  mk_home; owners; prop --due 2099-12-30T10:00
  A "$REF" --show > "$HOME/card"
  grep -q '^owner:      lumen-tea (Lumen Tea Co.)' "$HOME/card" || exit 1
  grep -q '^account:    @lumentea.example' "$HOME/card" || exit 1
  grep -q '^due:        2099-12-30 10:00 Asia/Kolkata (2099-12-30T04:30:00Z)' "$HOME/card" || exit 1
  grep -q "^digest:     $DIG" "$HOME/card" || exit 1
  assert_eq "$(grep -c '^  [12]\. sha256 ' "$HOME/card")" 2 media-lines
  assert_eq "$(state "$REF")" proposed
}

test_account_and_owner_checked() {
  mk_home; owners
  expect 3 L propose --owner lumen-tea --account @iradas.example --action instagram.post --text-file "$W/caption.txt"
  expect 4 L propose --owner nobody-here --account @x --action instagram.post --text-file "$W/caption.txt"
  expect 2 L propose --owner Lumen_Tea --account @lumentea.example --action instagram.post --text-file "$W/caption.txt"
  expect 2 L propose --owner lumen-tea --account @lumentea.example --action instagram.post
  printf '\377\376bad' > "$W/bad.txt"
  expect 2 L propose --owner lumen-tea --account @lumentea.example --action instagram.post --text-file "$W/bad.txt"
}

test_late_actions_expire() {
  mk_home; owners; prop --due 2026-01-01T10:00
  expect 3 AH "$REF" --digest "$DIG"
  grep -q '24 hours past' "$HOME/expect.out" || exit 1
  assert_eq "$(L expire | sed -n 's/^expired=//p')" 1 expired
  assert_eq "$(state "$REF")" expired
  expect 3 AH "$REF" --digest "$DIG"
}

test_migrations_idempotent() {
  mk_home; owners
  first=$(L migrate); second=$(L migrate)
  assert_eq "$first" "$second" same
  assert_eq "$(sql "select count(*) from schema_version")" 2 versions
  assert_eq "$(sql "select group_concat(version) from schema_version")" "1,2" order
  assert_eq "$(sql "pragma journal_mode")" wal wal
  # A later package adds a numbered file; it is applied once, after the others.
  R="$HOME/repo"; mkdir -p "$R"; cp -R "$REPO/business" "$R/"
  printf 'CREATE TABLE leads (id INTEGER PRIMARY KEY, owner TEXT NOT NULL);\n' > "$R/business/migrations/003-leads.sql"
  node "$R/business/scripts/kaito-ledger.mjs" migrate | grep -qx '003-leads' || exit 1
  node "$R/business/scripts/kaito-ledger.mjs" migrate > /dev/null
  assert_eq "$(sql "select count(*) from schema_version where version = 3")" 1 once
  # Editing an applied migration stops the ledger instead of drifting.
  printf '\n-- edited\n' >> "$R/business/migrations/001-ledger.sql"
  expect 1 node "$R/business/scripts/kaito-ledger.mjs" migrate
  grep -q 'changed after it was applied' "$HOME/expect.out" || exit 1
}

test_queue_add_close() {
  mk_home; owners
  id=$(L queue add --owner ira-das --kind callback --title "Call back the gallery" --due 2026-11-26 | sed -n 's/^id=//p')
  L queue list --owner ira-das | grep -q "^$id	open	ira-das	callback	2026-11-26	Call back the gallery" || exit 1
  T queue close "$id" > /dev/null
  assert_eq "$(L queue list --owner ira-das)" "" closed
  expect 3 L queue close "$id"
  expect 4 L queue close 999
  expect 2 L queue add --owner ira-das --kind "Call Back" --title x
  expect 2 L queue add --owner ira-das --kind callback --title x --due 2026-02-30
}

test_today_order_in_ist() {
  mk_home; owners
  NOW=2026-11-26T00:30:00+05:30  # 25 Nov 19:00 UTC: the UTC date is still yesterday
  q() { L queue add "$@" | sed -n 's/^id=//p'; }
  q1=$(q --owner lumen-tea --kind invoice-chase --title "Chase invoice LT-0042" --due 2026-11-25)
  q2=$(q --owner lumen-tea --kind callback --title "Call the Kolkata stockist" --due 2026-11-25T20:00:00Z)
  q3=$(q --owner lumen-tea --kind task --title "Tomorrow in IST" --due 2026-11-26T19:00:00Z)
  q4=$(q --owner lumen-tea --kind invoice-chase --title "Chase invoice LT-0039" --due 2026-11-20)
  q5=$(q --owner ira-das --kind callback --title "Reply to the publisher" --due 2026-11-26)
  q6=$(q --owner ira-das --kind task --title "Done already" --due 2026-11-26); L queue close "$q6" > /dev/null
  out=$(L propose --owner ira-das --account @iradas.example --action instagram.post --text-file "$W/caption.txt" --due 2026-11-28T10:00)
  ref=$(echo "$out" | sed -n 's/^ref=//p')
  ids=$(T --json --now "$NOW" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.items.map(i=>i.bucket+":"+i.id).join(" "))})')
  assert_eq "$ids" "overdue:$q4 overdue:$q1 today:$q5 today:$q2 later:$ref" order
  assert_eq "$(T --json --now "$NOW" | jget date)" 2026-11-26 ist-date
  assert_eq "$(T --json --now "$NOW" | jget timezone)" Asia/Kolkata tz
  # Per owner, and the text view starts with the IST date.
  T --owner lumen-tea --now "$NOW" > "$HOME/t"
  head -1 "$HOME/t" | grep -qx 'Needs you today, Thu 26 Nov 2026 (Asia/Kolkata)' || { cat "$HOME/t"; exit 1; }
  ! grep -q 'ira-das' "$HOME/t" || exit 1
  ! grep -q 'Tomorrow in IST' "$HOME/t" || exit 1
  sed -n 2p "$HOME/t" | grep -q "^overdue  Fri 20 Nov .*LT-0039  \[q$q4\]" || { cat "$HOME/t"; exit 1; }
  sed -n 4p "$HOME/t" | grep -q "^today    Thu 26 Nov 01:30 .*Kolkata stockist" || { cat "$HOME/t"; exit 1; }
  # An owner in another zone gets its own today.
  node -e 'const f=process.argv[1],j=JSON.parse(require("fs").readFileSync(f));j.timezone="America/New_York";require("fs").writeFileSync(f,JSON.stringify(j))' "$KAITO_HOME/owners/ira-das/owner.json"
  T --owner ira-das --json --now "$NOW" | jget date | grep -qx 2026-11-25 || exit 1
  # A whole-day item keeps its calendar date when the owner's zone changes.
  got=$(T --owner ira-das --json --now 2026-11-26T12:00:00-05:00 | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const i=JSON.parse(s).items.find(x=>x.id===process.argv[1]);console.log(i?`${i.bucket} ${i.due_local}`:"none")})' "$q5")
  assert_eq "$got" "today 2026-11-26" all-day-date
  expect 4 T --owner nobody-here
  T --owner lumen-tea --now 2026-12-20T09:00:00+05:30 | grep -c '^overdue' | grep -qx 4 || exit 1
}

test_brief_renders() {
  mk_home; owners
  NOW=2099-11-26T09:00:00+05:30
  L queue add --owner lumen-tea --kind invoice-chase --title "Chase invoice LT-0039" --due 2099-11-20 > /dev/null
  L queue add --owner lumen-tea --kind callback --title "Call the Kolkata stockist" --due 2099-11-28T11:00 > /dev/null
  L queue add --owner lumen-tea --kind task --title "Next week" --due 2099-12-01 > /dev/null
  prop --due 2099-11-27T10:00; p1=$REF
  prop --due 2099-11-29T18:00; ok_approve "$REF" "$DIG"; p2=$REF
  printf 'A second caption\n' > "$W/caption.txt"; prop; ok_approve "$REF" "$DIG"
  L claim "$REF" --digest "$DIG" > /dev/null; L record "$REF" --attempt 1 --result uncertain > /dev/null; p3=$REF
  T brief --owner lumen-tea --now "$NOW" > "$HOME/brief.md"
  head -1 "$HOME/brief.md" | grep -qx '# Week of Mon 23 Nov 2099: Lumen Tea Co.' || { cat "$HOME/brief.md"; exit 1; }
  for h in '## Awaiting your approval' '## Uncertain sends to check' '## Overdue' '## Due this week'; do
    grep -qx "$h" "$HOME/brief.md" || { echo "  missing $h"; cat "$HOME/brief.md"; exit 1; }
  done
  grep -qx -- "- Fri 27 Nov 10:00: Approve instagram.reel.publish on @lumentea.example (\`$p1\`)" "$HOME/brief.md" || { cat "$HOME/brief.md"; exit 1; }
  grep -q -- "Check whether instagram.reel.publish.*$p3" "$HOME/brief.md" || exit 1
  grep -qx -- '- Fri 20 Nov: Chase invoice LT-0039 (queue 1)' "$HOME/brief.md" || exit 1
  grep -qx -- '- Sat 28 Nov 11:00: Call the Kolkata stockist (queue 2)' "$HOME/brief.md" || exit 1
  grep -qx -- "- Sun 29 Nov 18:00: instagram.reel.publish on @lumentea.example goes out (\`$p2\`)" "$HOME/brief.md" || exit 1
  ! grep -q 'Next week' "$HOME/brief.md" || exit 1
  # An empty owner still renders every section.
  T brief --owner ira-das --now "$NOW" | grep -c '^None\.$' | grep -qx 4 || exit 1
  expect 2 T brief
}

test_claim_before_due_refused() {
  mk_home; owners; prop --due 2099-11-27T10:00; ok_approve "$REF" "$DIG"
  expect 3 L claim "$REF" --digest "$DIG"
  grep -q 'not due yet' "$HOME/expect.out" || exit 1
  assert_eq "$(state "$REF")" approved still-approved
  assert_eq "$(sql "select count(*) from attempts")" 0 no-attempt
}

test_late_ok_after_reconcile_failed() {
  mk_home; owners; prop; ok_approve "$REF" "$DIG"
  L claim "$REF" --digest "$DIG" > /dev/null
  L record "$REF" --attempt 1 --result uncertain > /dev/null
  L reconcile "$REF" --failed > /dev/null
  # The paused publisher wakes up and reports the send went through after all.
  L record "$REF" --attempt 1 --result ok --remote-id 1790 > /dev/null
  assert_eq "$(state "$REF")" reconciled
  assert_eq "$(L status "$REF" | sed -n 's/^remote_id=//p')" 1790 remote-id
  expect 3 L record "$REF" --attempt 1 --result ok
}

test_replace_cannot_reset_a_sent_action() {
  mk_home; owners; prop; ok_approve "$REF" "$DIG"
  L claim "$REF" --digest "$DIG" > /dev/null
  L record "$REF" --attempt 1 --result ok > /dev/null
  # INSERT OR REPLACE skips delete triggers; the insert triggers stop it instead.
  ! sql "insert or replace into actions select ref, owner, account, action, text_sha256, media_json, disclosure, due_at, payload_json, digest, 'approved', created_at, updated_at, approved_at, approved_via, remote_id, note from actions where ref = '$REF'" 2>/dev/null || exit 1
  ! sql "insert or replace into attempts (ref, n, digest, claimed_at) values ('$REF', 2, '$DIG', '2026-01-01T00:00:00Z')" 2>/dev/null || exit 1
  ! sql "delete from attempts" 2>/dev/null || exit 1
  assert_eq "$(state "$REF")" sent
}

test_card_escapes_terminal_controls() {
  mk_home; owners
  printf 'Fine print\033[2K\033[1A\rdisclosure: none\n\342\200\256gnp.evil\n\340\246\225\340\247\215\342\200\215\340\246\267\n' > "$W/caption.txt"
  prop
  A "$REF" --show > "$HOME/card"
  ! grep -q "$(printf '\033')" "$HOME/card" || { echo "  raw escape reached the card"; exit 1; }
  grep -q '^| Fine print\\u{001b}\[2K\\u{001b}\[1A$' "$HOME/card" || { cat "$HOME/card"; exit 1; }
  # A lone carriage return became a line end when the text was stored, so it starts its own payload line.
  grep -q '^| disclosure: none$' "$HOME/card" || exit 1
  grep -q '^disclosure: ai' "$HOME/card" || exit 1
  grep -q '^| \\u{202e}gnp.evil$' "$HOME/card" || exit 1
  # Bengali conjuncts keep their joiners.
  grep -q "^| $(printf '\340\246\225\340\247\215\342\200\215\340\246\267')$" "$HOME/card" || exit 1
  grep -q '^PROBLEM: the text holds 3 control or direction characters' "$HOME/card" || { cat "$HOME/card"; exit 1; }
}

test_digest_path_needs_a_host() {
  mk_home; owners; prop
  # No terminal and no agent host: a cron job or script, so no one saw a prompt.
  sig=$($NOAGENT node --input-type=module -e "import { agentSigns } from '$B/kaito-approve.mjs'; console.log(agentSigns().length)")
  if [ "$sig" != 0 ]; then echo "skip: tests run inside an agent session"; return 0; fi
  expect 3 $NOAGENT node "$B/kaito-approve.mjs" "$REF" --digest "$DIG" < /dev/null
  grep -q 'no agent host' "$HOME/expect.out" || exit 1
  assert_eq "$(state "$REF")" proposed
}

test_codex_allow_rule_refused() {
  mk_home; owners; prop
  mkdir -p "$HOME/.codex/rules"
  printf 'prefix_rule(pattern = ["node"], decision = "allow")\n' > "$HOME/.codex/rules/default.rules"
  # A stand-in codex process is the host: codex rules are read only under codex.
  mkdir -p "$HOME/bin"; ln -s "$(command -v node)" "$HOME/bin/codex"
  expect 3 env CODEX_HOME="$HOME/.codex" AI_AGENT=1 "$HOME/bin/codex" -e 'process.exitCode = require("child_process").spawnSync(process.execPath, process.argv.slice(1), { stdio: "inherit" }).status' \
    "$B/kaito-approve.mjs" "$REF" --digest "$DIG"
  grep -q 'default.rules allows \["node"\]' "$HOME/expect.out" || { cat "$HOME/expect.out"; exit 1; }
}

test_queue_checks_owner_and_ref() {
  mk_home; owners; prop
  expect 4 L queue add --owner nobody-here --kind task --title x
  expect 2 L queue add --owner ira-das --kind task --title x --ref "$REF"
  L queue add --owner lumen-tea --kind review --title "Look at the Reel" --ref "$REF" | grep -q '^id=' || exit 1
  expect 4 L queue add --owner lumen-tea --kind task --title x --ref act-20260101-00000000
  # Times a clock change skips or repeats are refused, not shifted.
  node -e 'const f=process.argv[1],j=JSON.parse(require("fs").readFileSync(f));j.timezone="America/New_York";require("fs").writeFileSync(f,JSON.stringify(j))' "$KAITO_HOME/owners/ira-das/owner.json"
  expect 2 L queue add --owner ira-das --kind task --title x --due 2026-03-08T02:30
  expect 2 L queue add --owner ira-das --kind task --title x --due 2026-11-01T01:30
  L queue add --owner ira-das --kind task --title x --due 2026-11-01T01:30-04:00 > /dev/null || exit 1
  expect 2 L queue add --owner ira-das --kind task --title x --due 2026-02-30T10:00Z
}

test_retry_keeps_idempotency_key() {
  mk_home; owners; prop; ok_approve "$REF" "$DIG"; first=$REF
  key=$(L claim "$REF" --digest "$DIG" | sed -n 's/^idempotency_key=//p'); assert_eq "$key" "$first" key-is-ref
  L record "$REF" --attempt 1 --result failed > /dev/null
  out=$(L propose --owner lumen-tea --account @lumentea.example --action instagram.reel.publish \
    --text-file "$W/caption.txt" --media "$W/reel.mp4" "$W/cover.png" --disclosure ai --retry-of "$first")
  REF=$(echo "$out" | sed -n 's/^ref=//p'); DIG=$(echo "$out" | sed -n 's/^digest=//p')
  ok_approve "$REF" "$DIG"
  assert_eq "$(L claim "$REF" --digest "$DIG" | sed -n 's/^idempotency_key=//p')" "$first" same-key
  # Only a failed send of the same payload to the same account is a retry.
  expect 3 L propose --owner lumen-tea --account @lumentea.example --action instagram.reel.publish --text-file "$W/caption.txt" --retry-of "$first"
  expect 3 L propose --owner lumen-tea --account @lumentea.example --action instagram.reel.publish \
    --text-file "$W/caption.txt" --media "$W/reel.mp4" "$W/cover.png" --retry-of "$REF"
}

test_ready_list_includes_undated() {
  mk_home; owners
  prop; ok_approve "$REF" "$DIG"; now_ref=$REF
  prop --due 2099-01-01T10:00; ok_approve "$REF" "$DIG"; later=$REF
  prop; waiting=$REF
  out=$(L list --ready)
  echo "$out" | grep -q "^$now_ref	approved" || { echo "$out"; exit 1; }
  ! echo "$out" | grep -q -e "$later" -e "$waiting" || { echo "$out"; exit 1; }
}

test_codex_env_without_ancestry_checks_rules() {
  mk_home; owners; prop
  mkdir -p "$HOME/.codex/rules"
  printf 'prefix_rule(pattern = ["node"], decision = "allow")\n' > "$HOME/.codex/rules/default.rules"
  expect 3 env CODEX_HOME="$HOME/.codex" CODEX_THREAD_ID=t1 node "$B/kaito-approve.mjs" "$REF" --digest "$DIG"
  grep -q 'default.rules allows' "$HOME/expect.out" || { cat "$HOME/expect.out"; exit 1; }
}

test_odd_timezones_refused() {
  mk_home; owners
  node -e 'const f=process.argv[1],j=JSON.parse(require("fs").readFileSync(f));j.timezone="Australia/Lord_Howe";require("fs").writeFileSync(f,JSON.stringify(j))' "$KAITO_HOME/owners/ira-das/owner.json"
  expect 2 L queue add --owner ira-das --kind task --title x --due 2026-04-05T01:45
  node -e 'const f=process.argv[1],j=JSON.parse(require("fs").readFileSync(f));j.timezone="Pacific/Apia";require("fs").writeFileSync(f,JSON.stringify(j))' "$KAITO_HOME/owners/ira-das/owner.json"
  expect 2 L queue add --owner ira-das --kind task --title x --due 2011-12-30
  L queue add --owner ira-das --kind task --title x --due 2011-12-31 > /dev/null || exit 1
}

test_attempt_identity_fixed() {
  mk_home; owners; prop; ok_approve "$REF" "$DIG"
  L claim "$REF" --digest "$DIG" > /dev/null
  ! sql "update attempts set n = 2 where ref = '$REF'" 2>/dev/null || exit 1
  ! sql "update attempts set claimed_at = '2020-01-01T00:00:00Z' where ref = '$REF'" 2>/dev/null || exit 1
  L record "$REF" --attempt 1 --result ok > /dev/null
  assert_eq "$(state "$REF")" sent
}
