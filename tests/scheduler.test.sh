#!/bin/sh
. "$(dirname "$0")/lib.sh"
B="$REPO/business/scripts"
ledger() { node "$B/kaito-ledger.mjs" "$@"; }
tick() { node "$B/kaito-tick.mjs" "$@"; }
state() { ledger status "$1" | sed -n 's/^state=//p'; }
fixture() {
  mk_home
  mkdir -p "$KAITO_HOME/owners/lumen-tea"
  printf '%s\n' '{"id":"lumen-tea","name":"Lumen Tea Co.","kind":"company","channels":{"instagram":"@lumentea.example"},"cloud_ok":true}' > "$KAITO_HOME/owners/lumen-tea/owner.json"
  printf 'Fixture caption\n' > "$HOME/caption"
  out=$(ledger propose --owner lumen-tea --account @lumentea.example --action noop-test --text-file "$HOME/caption" --due "$1") || exit 1
  ref=$(printf '%s\n' "$out" | sed -n 's/^ref=//p')
  digest=$(printf '%s\n' "$out" | sed -n 's/^digest=//p')
}
approve_fixture() {
  fixture_approve "$ref" "$digest" >/dev/null || exit 1
}

test_due_once_and_prepare() {
  fixture 2099-12-01T00:02:00Z
  KAITO_TEST_NOW=2099-12-01T00:00:00Z tick > "$HOME/unapproved" || exit 1
  assert_eq "$(cat "$HOME/unapproved")" "" unapproved
  approve_fixture
  KAITO_TEST_NOW=2099-12-01T00:00:00Z tick > "$HOME/early" || exit 1
  grep -qx "prepared=$ref" "$HOME/early" || exit 1
  assert_eq "$(state "$ref")" approved early
  KAITO_TEST_NOW=2099-12-01T00:02:00Z tick > "$HOME/due" || exit 1
  grep -qx "sent=$ref" "$HOME/due" || exit 1
  KAITO_TEST_NOW=2099-12-01T00:02:00Z tick > "$HOME/again" || exit 1
  assert_eq "$(cat "$HOME/again")" "" second-tick
  assert_eq "$(state "$ref")" sent state
  ledger status "$ref" | grep -qx "remote_id=noop-prepared-$ref" || exit 1
}

test_crash_is_reconciled_manually() {
  fixture 2099-12-01T00:02:00Z; approve_fixture
  KAITO_TEST_NOW=2099-12-01T00:02:00Z KAITO_TEST_NOOP_CRASH=1 tick > "$HOME/crash" 2>&1 && exit 1
  assert_eq "$(state "$ref")" claimed after-kill
  KAITO_TEST_NOW=2099-12-01T00:33:00Z tick || exit 1
  assert_eq "$(state "$ref")" uncertain after-stale
  ledger reconcile | grep -q "^$ref	uncertain	" || exit 1
}

test_worker() {
  mk_home
  node "$TESTS_DIR/fixtures/scheduler-worker.mjs" "$REPO"
}
