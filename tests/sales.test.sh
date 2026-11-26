#!/bin/sh
. "$(dirname "$0")/lib.sh"
B="$REPO/business/scripts"
leads() { node "$B/kaito-leads.mjs" "$@"; }
test_sales_flow() {
  mk_home
  mkdir -p "$KAITO_HOME/owners/lumen-tea" "$KAITO_HOME/owners/ira-das"
  printf '%s\n' '{"id":"lumen-tea","name":"Lumen Tea Co.","timezone":"Asia/Kolkata"}' > "$KAITO_HOME/owners/lumen-tea/owner.json"
  printf '%s\n' '{"id":"ira-das","name":"Ira Das"}' > "$KAITO_HOME/owners/ira-das/owner.json"
  cat > "$HOME/leads.csv" <<'CSV'
name,email,company
"Robin, Lee",robin@example.test,Example
Bad,not-an-email,Example
CSV
  leads import "$HOME/leads.csv" --owner lumen-tea > "$HOME/import" && exit 1
  grep -q 'imported=1' "$HOME/import" || exit 1
  grep -q 'bad_rows=3' "$HOME/import" || exit 1
  leads list --owner lumen-tea --json | grep -q 'Robin, Lee' || exit 1
  leads move 1 --owner ira-das --stage outreach --note x >/dev/null 2>&1 && exit 1
  leads move 1 --owner lumen-tea --stage qualify --note 'Need known; budget unknown' >/dev/null || exit 1
  leads move 1 --owner lumen-tea --stage outreach --note 'Draft prepared' >/dev/null || exit 1
  leads touch 1 --owner lumen-tea --note 'Follow up' --due 2020-01-01 > "$HOME/touch" || exit 1
  q=$(sed -n 's/^queue_id=//p' "$HOME/touch")
  leads callbacks --owner lumen-tea --json | grep -q 'Robin, Lee' || exit 1
  node "$B/kaito-today.mjs" --owner lumen-tea --json | grep -q 'callback' || exit 1
  leads move 1 --owner lumen-tea --stage review --note 'Claims checked' >/dev/null || exit 1
  leads move 1 --owner lumen-tea --stage retro --note 'Lost; reason not given' >/dev/null || exit 1
  node "$B/kaito-ledger.mjs" queue close "$q" >/dev/null || exit 1
  assert_eq "$(leads callbacks --owner lumen-tea --json)" '[]' callbacks-closed
  node "$B/kaito-today.mjs" --owner lumen-tea --json | grep -q callback && exit 1
  return 0
}
test_voice() {
  mk_home
  mkdir -p "$KAITO_HOME/owners/lumen-tea"
  printf '%s\n' '{"id":"lumen-tea"}' > "$KAITO_HOME/owners/lumen-tea/owner.json"
  cat > "$HOME/sent.mbox" <<'MAIL'
From sender@example.test Thu Nov 26 10:00:00 2026
From: sender@example.test
To: buyer@example.test
Subject: Hello
Content-Type: text/plain; charset=utf-8

Hello there. A confidential phrase stays here.
MAIL
  python3 "$B/kaito-voice.py" "$HOME/sent.mbox" --owner lumen-tea > /dev/null || exit 1
  grep -q '1 sent messages' "$KAITO_HOME/owners/lumen-tea/voice.md" || exit 1
  grep -q 'confidential phrase' "$KAITO_HOME/owners/lumen-tea/voice.md" && exit 1
  python3 "$B/kaito-voice.py" "$HOME/sent.mbox" --owner lumen-tea >/dev/null 2>&1 && exit 1
  return 0
}
