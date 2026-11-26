#!/bin/sh
. "$(dirname "$0")/lib.sh"
B="$REPO/business/scripts"
M() { node "$B/kaito-money.mjs" "$@"; }
L() { node "$B/kaito-ledger.mjs" "$@"; }
T() { node "$B/kaito-today.mjs" "$@"; }
get() { node -e 'let v=JSON.parse(require("node:fs").readFileSync(0));for(const k of process.argv[1].split("."))v=v[k];console.log(v)' "$1"; }
setup_money() {
  mk_home
  for owner in lumen-tea ira-das; do
    mkdir -p "$KAITO_HOME/owners/$owner"
    printf '{"address":"12 Example Lane","export_mode":"lut"}\n' > "$KAITO_HOME/owners/$owner/money.json"
  done
  printf '%s\n' '{"id":"lumen-tea","kind":"company","name":"Lumen Tea Co.","gstin":"19ABCDE1234F1Z5","channels":{"billing":"billing@example.test"}}' > "$KAITO_HOME/owners/lumen-tea/owner.json"
  printf '%s\n' '{"id":"ira-das","kind":"person","name":"Ira Das","channels":{"billing":"ira@example.test"}}' > "$KAITO_HOME/owners/ira-das/owner.json"
  input 19 IN
}
input() {
  cat > "$HOME/in.json" <<JSON
{"client":{"name":"<Client>","address":"10 Example Road","email":"buyer@example.test","state_code":"$1","country":"$2"},"due_date":"2020-01-01","lines":[{"description":"Loose tea","quantity":"1.5","unit":"kg","unit_paise":103,"hsn_sac":"0902","gst_bps":1800,"internal_cost":987654,"profit_margin":123456}]}
JSON
}
draft() { M draft "$1" --owner "$2" --input "$HOME/in.json" | get id; }
check() { M check "$1" --owner "$2"; }
propose() { M propose "$1" --owner "$2" --account "$3"; }
expect() {
  wanted=$1; shift
  "$@" > "$HOME/expect.out" 2>&1
  assert_eq "$?" "$wanted" "$* ($(cat "$HOME/expect.out"))"
}
sql() {
  node --no-warnings -e 'const d=new (require("node:sqlite").DatabaseSync)(process.argv[1]);d.exec("PRAGMA foreign_keys=ON");console.log(d.prepare(process.argv[2]).all().map(Object.values).join("\n"))' "$KAITO_HOME/business/ledger.db" "$1"
}
# An isolated fixture supplies the approval row. This never calls a human approval path.
fixture_yes() {
  sql "INSERT INTO approvals (ref,digest,at,via) SELECT ref,digest,updated_at,'terminal' FROM actions WHERE ref='$1'" >/dev/null &&
  sql "UPDATE actions SET state='approved', approved_at=updated_at, approved_via='terminal' WHERE ref='$1'" >/dev/null
}
issue() { M issue "$1" --owner "$2" --ref "$3" --digest "$4"; }
test_gst_and_decimal_rounding() {
  setup_money
  doc=$(draft invoice lumen-tea)
  out=$(check "$doc" lumen-tea)
  assert_eq "$(echo "$out" | get totals.net)" 155 half-up-line-net
  assert_eq "$(echo "$out" | get totals.cgst)" 14 cgst
  assert_eq "$(echo "$out" | get totals.sgst)" 14 sgst
  assert_eq "$(echo "$out" | get totals.total)" 183 total-in-paise
  input 27 IN; doc=$(draft invoice lumen-tea)
  assert_eq "$(check "$doc" lumen-tea | get totals.igst)" 28 inter-state
  input '' GB; doc=$(draft invoice lumen-tea)
  assert_eq "$(check "$doc" lumen-tea | get totals.igst)" 0 lut-nil
  printf '%s\n' '{"address":"12 Example Lane","export_mode":"igst-paid"}' > "$KAITO_HOME/owners/lumen-tea/money.json"
  doc=$(draft invoice lumen-tea)
  assert_eq "$(check "$doc" lumen-tea | get totals.igst)" 28 export-paid
  input 19 IN; doc=$(draft invoice ira-das)
  assert_eq "$(check "$doc" ira-das | get totals.total)" 155 unregistered
  expect 4 check "$doc" lumen-tea
}
test_exact_issue_concurrent_revision_and_credit() {
  setup_money
  first=$(draft invoice lumen-tea); second=$(draft invoice lumen-tea)
  old=$(draft quote lumen-tea)
  M revise "$old" --owner lumen-tea --input "$HOME/in.json" > "$HOME/revision" || exit 1
  assert_eq "$(get previous_id < "$HOME/revision")" "$old" revision-parent
  expect 3 propose "$old" lumen-tea billing@example.test
  assert_eq "$(sql 'SELECT count(*) FROM money_issues')" 0 drafts-and-revisions-have-no-number
  p=$(propose "$first" lumen-tea billing@example.test)
  q=$(propose "$second" lumen-tea billing@example.test)
  ar=$(echo "$p" | get ref); ad=$(echo "$p" | get digest)
  br=$(echo "$q" | get ref); bd=$(echo "$q" | get digest)
  expect 3 issue "$first" lumen-tea "$ar" "$ad"
  fixture_yes "$ar" && fixture_yes "$br" || exit 1
  expect 3 L claim "$ar" --digest "$ad"
  expect 3 issue "$second" lumen-tea "$ar" "$ad"
  ( issue "$first" lumen-tea "$ar" "$ad" > "$HOME/a" 2>&1; echo $? > "$HOME/rc-a" ) &
  a=$!
  ( issue "$second" lumen-tea "$br" "$bd" > "$HOME/b" 2>&1; echo $? > "$HOME/rc-b" ) &
  b=$!; wait "$a"; wait "$b"
  assert_eq "$(sort "$HOME"/rc-* | tr '\n' ' ')" "0 3 " one-winner
  if [ "$(cat "$HOME/rc-a")" = 0 ]; then winner=$first; loser=$second; wr=$ar; else winner=$second; loser=$first; wr=$br; fi
  assert_eq "$(sql 'SELECT sequence FROM money_issues')" 1 first-sequence
  assert_eq "$(sql 'SELECT count(*) FROM attempts')" 1 stale-candidate-did-not-claim
  assert_eq "$(L status "$wr" --json | get state)" sent atomic-ledger-result
  expect 3 M revise "$winner" --owner lumen-tea --input "$HOME/in.json"
  expect 1 sql "DELETE FROM money_documents WHERE id='$winner'"
  expect 1 sql "UPDATE money_issues SET sequence=9"
  M export "$winner" --owner lumen-tea --html "$HOME/out.html" || exit 1
  sha=$(L status "$wr" --json | get media.0)
  cmp "$HOME/out.html" "$sha" || exit 1
  ! grep -Eq '987654|123456|internal_cost|profit_margin|<Client>' "$HOME/out.html" || exit 1
  grep -q '&lt;Client&gt;' "$HOME/out.html" || exit 1
  p=$(propose "$loser" lumen-tea billing@example.test)
  ar=$(echo "$p" | get ref); ad=$(echo "$p" | get digest)
  fixture_yes "$ar" || exit 1
  issue "$loser" lumen-tea "$ar" "$ad" > /dev/null || exit 1
  assert_eq "$(sql 'SELECT sequence FROM money_issues ORDER BY sequence' | tr '\n' ' ')" "1 2 " no-gap
  M aging --owner lumen-tea --sync >/dev/null || exit 1
  assert_eq "$(T --owner lumen-tea --json | get items.length)" 2 aging-before-credit
  credit=$(M credit "$winner" --owner lumen-tea --reason "Returned goods" | get id)
  p=$(propose "$credit" lumen-tea billing@example.test)
  ar=$(echo "$p" | get ref); ad=$(echo "$p" | get digest)
  fixture_yes "$ar" || exit 1
  assert_eq "$(issue "$credit" lumen-tea "$ar" "$ad" | get original_id)" "$winner" original-retained
  expect 3 M credit "$winner" --owner lumen-tea --reason "Again"
  assert_eq "$(T --owner lumen-tea --json | get items.length)" 1 credit-closes-chase
}
test_aging_today_and_chase_draft() {
  setup_money
  d=$(draft invoice ira-das)
  p=$(propose "$d" ira-das ira@example.test)
  r=$(echo "$p" | get ref); h=$(echo "$p" | get digest)
  fixture_yes "$r" || exit 1
  issue "$d" ira-das "$r" "$h" >/dev/null || exit 1
  for pair in '2020-01-31 0-30' '2020-02-01 31-60' '2020-03-01 31-60' '2020-03-02 61-90' '2020-03-31 61-90' '2020-04-01 90+'; do
    set -- $pair
    assert_eq "$(M aging --owner ira-das --as-of "$1" | get 0.bucket)" "$2" "$1"
  done
  M aging --owner ira-das --sync >/dev/null && M aging --owner ira-das --sync >/dev/null || exit 1
  assert_eq "$(T --owner ira-das --json | get items.length)" 1 deduplicated
  assert_eq "$(T --owner ira-das --json | get items.0.kind)" invoice-chase today-queue
  M chase "$d" --owner ira-das > "$HOME/chase.json" || exit 1
  assert_eq "$(get to < "$HOME/chase.json")" buyer@example.test draft-recipient
  assert_eq "$(sql 'SELECT count(*) FROM actions')" 1 no-send-proposal
  M payment "$d" --owner ira-das --paise 100 --reference test-1 >/dev/null || exit 1
  M payment "$d" --owner ira-das --paise 100 --reference test-1 >/dev/null || exit 1
  assert_eq "$(M aging --owner ira-das | get 0.balance_paise)" 55 partial-payment-idempotent
  M payment "$d" --owner ira-das --paise 55 --reference test-2 >/dev/null || exit 1
  assert_eq "$(T --owner ira-das --json | get items.length)" 0 paid-queue-closed
}
test_financial_year_ist_and_independent_series() {
  setup_money
  printf '%s\n' 'Date.now = () => Date.parse(process.env.TEST_MONEY_NOW);' > "$HOME/clock.mjs"
  NODE_OPTIONS="--import=$HOME/clock.mjs"
  TEST_MONEY_NOW=2027-03-31T18:29:59Z
  export NODE_OPTIONS TEST_MONEY_NOW

  march=$(draft invoice lumen-tea)
  p=$(propose "$march" lumen-tea billing@example.test)
  assert_eq "$(echo "$p" | get candidate)" INV-2026-000001 before-ist-midnight
  r=$(echo "$p" | get ref); h=$(echo "$p" | get digest)
  fixture_yes "$r" || exit 1
  assert_eq "$(issue "$march" lumen-tea "$r" "$h" | get number)" INV-2026-000001 march-issue

  april=$(draft invoice lumen-tea)
  p=$(propose "$april" lumen-tea billing@example.test)
  assert_eq "$(echo "$p" | get candidate)" INV-2026-000002 march-candidate
  r=$(echo "$p" | get ref); h=$(echo "$p" | get digest)
  fixture_yes "$r" || exit 1
  TEST_MONEY_NOW=2027-03-31T18:30:00Z
  expect 3 issue "$april" lumen-tea "$r" "$h"
  p=$(propose "$april" lumen-tea billing@example.test)
  assert_eq "$(L status "$r" --json | get state)" rejected old-ref-retired
  r=$(echo "$p" | get ref); h=$(echo "$p" | get digest)
  fixture_yes "$r" || exit 1
  assert_eq "$(issue "$april" lumen-tea "$r" "$h" | get number)" INV-2027-000001 new-year-issue
  assert_eq "$(issue "$april" lumen-tea "$r" "$h" | get number)" INV-2027-000001 retry-returns-receipt

  other=$(draft invoice ira-das)
  assert_eq "$(propose "$other" ira-das ira@example.test | get candidate)" INV-2027-000001 other-owner
  q=$(draft quote lumen-tea)
  p=$(propose "$q" lumen-tea billing@example.test)
  r=$(echo "$p" | get ref); h=$(echo "$p" | get digest)
  fixture_yes "$r" || exit 1
  assert_eq "$(issue "$q" lumen-tea "$r" "$h" | get number)" Q-2027-000001 quote-series
}
test_tampered_approval_artifact_consumes_no_number() {
  setup_money
  d=$(draft invoice lumen-tea)
  p=$(propose "$d" lumen-tea billing@example.test)
  r=$(echo "$p" | get ref); h=$(echo "$p" | get digest)
  fixture_yes "$r" || exit 1
  artifact=$(L status "$r" --json | get media.0)
  chmod u+w "$artifact"
  printf '%s\n' 'changed bytes' >> "$artifact"
  expect 3 issue "$d" lumen-tea "$r" "$h"
  assert_eq "$(sql 'SELECT count(*) FROM money_issues')" 0 no-number
  assert_eq "$(sql 'SELECT count(*) FROM attempts')" 0 no-claim
}
