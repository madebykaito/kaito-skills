#!/bin/sh
. "$(dirname "$0")/lib.sh"
B="$REPO/business/scripts"
S() { node "$B/kaito-support.mjs" "$@"; }
T() { node "$B/kaito-today.mjs" "$@"; }
init_owner() {
  node "$B/kaito-owner.mjs" add "$1" --name "$2" --kind company >/dev/null || exit 1
  printf '%s\n' '[{"category":"delivery","keywords":["delivery","tracking"],"reply":"Please share the order number so we can check the shipment."},{"category":"delivery","keywords":["delivery"],"reply":"We can look up your delivery."}]' > "$KAITO_HOME/owners/$1/faq.json"
}
test_maildir_triage_queue_and_reply_draft() {
  mk_home
  init_owner lumen-tea 'Lumen Tea Co.'
  init_owner ira-das 'Ira Das'
  node -e 'const fs=require("fs"); const p=process.argv[1]; const o=JSON.parse(fs.readFileSync(p)); o.channels={email:"tea@example.test"}; fs.writeFileSync(p,JSON.stringify(o))' "$KAITO_HOME/owners/lumen-tea/owner.json"
  S --owner lumen-tea --maildir "$TESTS_DIR/fixtures/maildir" > "$HOME/triage" || exit 1
  S --owner lumen-tea --maildir "$TESTS_DIR/fixtures/maildir" > "$HOME/again" || exit 1
  cmp "$HOME/triage" "$HOME/again" || exit 1
  T --owner lumen-tea --json > "$HOME/today" || exit 1
  T --owner ira-das --json > "$HOME/other" || exit 1
  node - "$HOME" <<'JS'
const fs = require('fs'), assert = require('node:assert/strict'), dir = process.argv[2];
const read = f => JSON.parse(fs.readFileSync(dir + '/' + f));
const {owner, items} = read('triage');
assert.equal(owner, 'lumen-tea');
assert.equal(items.length, 2);
const [high, normal] = items;
assert.equal(high.urgency, 'high');
assert.equal(high.category, 'delivery');
assert.equal(high.customer.email, 'guest@example.test');
assert.equal(high.reply.to, 'reply@example.test');
assert.equal(high.reply.in_reply_to, '<delivery@example.test>');
assert.equal(high.drafts.length, 2);
assert.match(high.drafts[0].body, /order number/);
assert.ok(high.drafts[0].score > high.drafts[1].score);
assert.equal(normal.category, 'general');
assert.equal(normal.drafts.length, 1);
assert.equal(read('today').items.filter(x => x.kind === 'support-reply').length, 2);
assert.equal(read('other').items.length, 0);
JS
}

test_maildir_requires_real_subdirectories() {
  skip_on_win "symlinks" && return 0
  mk_home
  init_owner fixture 'Fixture Owner'
  mkdir -p "$HOME/empty"
  for part in cur new; do
    maildir="$HOME/maildir-$part"
    mkdir -p "$maildir/cur" "$maildir/new"
    rmdir "$maildir/$part"
    ln -s "$HOME/empty" "$maildir/$part" || exit 1
    S --owner fixture --maildir "$maildir" > "$HOME/triage" 2> "$HOME/error"; rc=$?
    assert_eq "$rc" 1 "$part"
    [ ! -s "$HOME/triage" ] || exit 1
    assert_no "$KAITO_HOME/business/ledger.db"
    grep -q 'could not read maildir inbox' "$HOME/error" || exit 1
  done
}

test_mbox_and_email_approval_card() {
  mk_home
  init_owner lumen-tea 'Lumen Tea Co.'
  node -e 'const fs=require("fs"); const p=process.argv[1]; const o=JSON.parse(fs.readFileSync(p)); o.channels={email:"tea@example.test"}; fs.writeFileSync(p,JSON.stringify(o))' "$KAITO_HOME/owners/lumen-tea/owner.json"
  python3 - "$TESTS_DIR/fixtures/maildir" "$HOME/export" <<'PY'
import mailbox
import sys
from pathlib import Path
box = mailbox.mbox(sys.argv[2])
for file in sorted((Path(sys.argv[1]) / "new").iterdir()):
    box.add(file.read_bytes())
box.close()
PY
  S --mbox "$HOME/export" --no-queue > "$HOME/triage" || exit 1
  assert_no "$KAITO_HOME/business/ledger.db"
  node - "$HOME" <<'JS'
const fs = require('fs'), assert = require('node:assert/strict'), dir = process.argv[2];
const {items} = JSON.parse(fs.readFileSync(dir + '/triage'));
assert.equal(items.length, 2);
assert.equal(items[0].queue_id, undefined);
fs.writeFileSync(dir + '/reply', items[0].drafts[0].body);
JS
  [ $? = 0 ] || exit 1
  out=$(node "$B/kaito-email.mjs" propose --owner lumen-tea --to reply@example.test \
    --subject 'Re: Urgent delivery tracking' --in-reply-to '<delivery@example.test>' \
    --body-file "$HOME/reply") || exit 1
  ref=$(printf '%s\n' "$out" | sed -n 's/^ref=//p')
  node "$B/kaito-approve.mjs" "$ref" --show > "$HOME/card" || exit 1
  grep -q '<delivery@example.test>' "$HOME/card" &&
    grep -q 'Please share the order number' "$HOME/card"
}
