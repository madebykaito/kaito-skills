#!/bin/sh
. "$(dirname "$0")/lib.sh"
B="$REPO/business/scripts"
E() { node "$B/kaito-email.mjs" "$@"; }
L() { node "$B/kaito-ledger.mjs" "$@"; }
expect() {
  want=$1; shift
  rc=0; "$@" > "$HOME/result" 2>&1 || rc=$?
  assert_eq "$rc" "$want" "$(cat "$HOME/result")"
}
owner() {
  node "$B/kaito-owner.mjs" add lumen-tea --name 'Lumen Tea Co.' --kind company >/dev/null
  node -e 'const fs=require("fs"); const p=process.argv[1]; const o=JSON.parse(fs.readFileSync(p)); o.channels={email:"tea@example.test"}; o.keys={smtp:process.argv[2],ses:process.argv[2],listmonk:process.argv[2]}; o.email_rate_per_hour=1; fs.writeFileSync(p,JSON.stringify(o))' "$KAITO_HOME/owners/lumen-tea/owner.json" "$HOME/engine.json"
  printf '%s\n' '{"version":1,"cloud":{"ses":{"granted":true}}}' > "$KAITO_HOME/owners/lumen-tea/consent.json"
  printf '%s\n' 'Tea & cakes {{literal}}' > "$HOME/body"
  printf '%s' 'attachment bytes' > "$HOME/menu.txt"
}
draft() {
  E --owner lumen-tea --engine "$1" --to guest@example.test --subject 'Tea {{special}}' \
    --body-file "$HOME/body" --attach "$HOME/menu.txt" \
    --unsubscribe https://example.test/leave --one-click
}
proposal() {
  engine=$1; shift
  out=$(E propose --owner lumen-tea --engine "$engine" --to guest@example.test --subject 'Tea {{special}}' \
    --body-file "$HOME/body" --attach "$HOME/menu.txt" --unsubscribe https://example.test/leave --one-click "$@") || exit 1
  REF=$(printf '%s\n' "$out" | sed -n 's/^ref=//p')
  DIG=$(printf '%s\n' "$out" | sed -n 's/^digest=//p')
  [ -n "$REF" ] && [ ${#DIG} = 64 ] || exit 1
}
approve_fixture() {
  # Seed the synthetic founder approval only in the isolated test database.
  node --input-type=module - "$KAITO_HOME/business/ledger.db" "$REF" "$DIG" <<'JS'
import { DatabaseSync } from 'node:sqlite';
const [file, ref, digest] = process.argv.slice(2);
const db = new DatabaseSync(file);
db.prepare("INSERT INTO approvals (ref,digest,via,at) VALUES (?,?,'terminal',?)").run(ref,digest,new Date().toISOString());
db.prepare("UPDATE actions SET state='approved' WHERE ref=?").run(ref);
JS
}
start_sink() {
  python3 "$TESTS_DIR/fixtures/mail-sink.py" "$1" "$HOME" &
  sink_pid=$!
  trap 'kill "$sink_pid" 2>/dev/null || :; wait "$sink_pid" 2>/dev/null || :' EXIT
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ ! -s "$HOME/engine.json" ] || return 0
    sleep 0.2
  done
  echo "loopback sink did not start" >&2
  exit 1
}
state() { L status "$REF" | sed -n 's/^state=//p'; }

test_draft_and_dnc_at_both_gates() {
  mk_home; owner
  expect 0 draft smtp
  assert_no "$KAITO_HOME/business/ledger.db"
  E dnc add GUEST@example.test --owner lumen-tea >/dev/null || exit 1
  expect 3 E propose --owner lumen-tea --to guest@example.test --subject Tea --body-file "$HOME/body"
  E dnc remove guest@example.test --owner lumen-tea >/dev/null || exit 1
  proposal smtp
  node "$B/kaito-approve.mjs" "$REF" --show > "$HOME/card" || exit 1
  grep -q 'guest@example.test' "$HOME/card" && grep -q 'menu.txt' "$HOME/card" || exit 1
  approve_fixture || exit 1
  E dnc add guest@example.test --owner lumen-tea >/dev/null || exit 1
  expect 3 L claim "$REF" --digest "$DIG"
  assert_eq "$(state)" approved blocked
}

test_smtp_exact_payload_and_claim_race() {
  mk_home; owner; start_sink smtp
  proposal smtp
  expect 3 E send "$REF" --digest "$DIG" --owner lumen-tea
  approve_fixture || exit 1
  expect 3 E send "$REF" --digest "$(printf '%064d' 0)" --owner lumen-tea
  printf 'edited after approval' > "$HOME/body"
  printf 'edited after approval' > "$HOME/menu.txt"
  E send "$REF" --digest "$DIG" --owner lumen-tea > "$HOME/first" 2>&1 & first=$!
  E send "$REF" --digest "$DIG" --owner lumen-tea > "$HOME/second" 2>&1 & second=$!
  a=0; wait "$first" || a=$?
  b=0; wait "$second" || b=$?
  case "$a:$b" in 0:3|3:0) ;; *) cat "$HOME/first" "$HOME/second"; exit 1 ;; esac
  assert_eq "$(state)" sent smtp
  assert_eq "$(cat "$HOME/delivered")" smtp delivered
  proposal smtp
  approve_fixture || exit 1
  expect 3 E send "$REF" --digest "$DIG" --owner lumen-tea
  grep -q 'rate limit' "$HOME/result" || { cat "$HOME/result"; exit 1; }
  assert_eq "$(state)" approved rate-limited
}

test_ses_signed_raw_email() {
  mk_home; owner; start_sink ses
  proposal ses; approve_fixture || exit 1
  expect 3 E send "$REF" --digest "$DIG" --owner lumen-tea
  expect 0 E send "$REF" --digest "$DIG" --owner lumen-tea --allow-cloud
  assert_eq "$(state)" sent ses
  assert_eq "$(cat "$HOME/delivered")" ses delivered
}

test_listmonk_transactional_email() {
  mk_home; owner; start_sink listmonk
  proposal listmonk --template 7; approve_fixture || exit 1
  expect 0 E send "$REF" --digest "$DIG" --owner lumen-tea
  assert_eq "$(state)" sent listmonk
  assert_eq "$(cat "$HOME/delivered")" listmonk delivered
}

test_missing_smtp_ack_is_uncertain() {
  mk_home; owner; start_sink smtp-drop
  proposal smtp; approve_fixture || exit 1
  expect 3 E send "$REF" --digest "$DIG" --owner lumen-tea
  assert_eq "$(state)" uncertain smtp-drop
  expect 3 E send "$REF" --digest "$DIG" --owner lumen-tea
}

test_two_approved_retries_share_one_send() {
  mk_home; owner; start_sink smtp
  node -e 'const fs=require("fs"); const p=process.argv[1]; const o=JSON.parse(fs.readFileSync(p)); o.email_rate_per_hour=30; fs.writeFileSync(p,JSON.stringify(o))' "$KAITO_HOME/owners/lumen-tea/owner.json"
  touch "$HOME/refuse"
  proposal smtp; approve_fixture || exit 1
  old_ref=$REF
  expect 1 E send "$REF" --digest "$DIG" --owner lumen-tea
  assert_eq "$(state)" failed rejected
  rm "$HOME/refuse"
  proposal smtp --retry-of "$old_ref"; approve_fixture || exit 1
  first_ref=$REF; first_digest=$DIG
  proposal smtp --retry-of "$old_ref"; approve_fixture || exit 1
  expect 0 E send "$first_ref" --digest "$first_digest" --owner lumen-tea
  expect 3 E send "$REF" --digest "$DIG" --owner lumen-tea
  grep -q 'already been accepted' "$HOME/result" || { cat "$HOME/result"; exit 1; }
  assert_eq "$(cat "$HOME/delivered")" smtp delivered
}

test_scheduler_sends_due_email_once() {
  mk_home; owner; start_sink smtp
  proposal smtp --due "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  approve_fixture || exit 1
  node "$B/kaito-tick.mjs" > "$HOME/tick" && grep -qx "sent=$REF" "$HOME/tick" || exit 1
  node "$B/kaito-tick.mjs" > "$HOME/tick" || exit 1
  assert_eq "$(cat "$HOME/tick")" "" second-tick
  assert_eq "$(cat "$HOME/delivered")" smtp once
  assert_eq "$(state)" sent recorded
}
