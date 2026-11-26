#!/bin/sh
. "$(dirname "$0")/lib.sh"
test_refuses_unapproved() {
  mk_home
  mkdir -p "$KAITO_HOME/owners/lumen-tea"
  printf '%s\n' '{"id":"lumen-tea","name":"Lumen Tea Co.","kind":"company","channels":{"linkedin":"integration-1"}}' > "$KAITO_HOME/owners/lumen-tea/owner.json"
  printf '%s\n' '{"content":"Hello","settings":{"__type":"linkedin"}}' > "$HOME/post.json"
  out=$(node "$REPO/business/scripts/kaito-ledger.mjs" propose --owner lumen-tea --account integration-1 --action social.linkedin.publish --text-file "$HOME/post.json" --json) || exit 1
  ref=$(printf '%s' "$out" | node -pe 'JSON.parse(require("fs").readFileSync(0)).ref')
  digest=$(printf '%s' "$out" | node -pe 'JSON.parse(require("fs").readFileSync(0)).digest')
  POSTIZ_URL=http://127.0.0.1:1 POSTIZ_KEY_FILE="$HOME/key" node "$REPO/business/scripts/kaito-social-publish.mjs" "$ref" --digest "$digest" > "$HOME/out" 2>&1; code=$?
  assert_eq "$code" 3 unapproved
}

test_publish_once_and_uncertain() {
  mk_home
  mkdir -p "$KAITO_HOME/owners/lumen-tea"
  printf '%s\n' '{"id":"lumen-tea","name":"Lumen Tea Co.","kind":"company","channels":{"linkedin":"integration-1"}}' > "$KAITO_HOME/owners/lumen-tea/owner.json"
  printf '%s\n' '{"content":"Hello","settings":{"__type":"linkedin"},"media_names":["media.png"]}' > "$HOME/post.json"
  printf 'sample media' > "$HOME/media.png"
  printf 'test-key' > "$HOME/key"
  FAKE_PORT="$HOME/port" FAKE_POSTS="$HOME/posts" FAKE_UPLOAD="$HOME/upload"; export FAKE_PORT FAKE_POSTS FAKE_UPLOAD
  node "$REPO/tests/social-postiz-fake.mjs" & pid=$!
  trap 'kill "$pid" 2>/dev/null || :' EXIT
  i=0; while [ ! -f "$FAKE_PORT" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i+1)); done
  POSTIZ_URL="http://127.0.0.1:$(cat "$FAKE_PORT")" POSTIZ_KEY_FILE="$HOME/key"; export POSTIZ_URL POSTIZ_KEY_FILE
  out=$(node "$REPO/business/scripts/kaito-ledger.mjs" propose --owner lumen-tea --account integration-1 --action social.linkedin.publish --text-file "$HOME/post.json" --media "$HOME/media.png" --json) || exit 1
  ref=$(printf '%s' "$out" | node -pe 'JSON.parse(require("fs").readFileSync(0)).ref')
  digest=$(printf '%s' "$out" | node -pe 'JSON.parse(require("fs").readFileSync(0)).digest')
  fixture_approve "$ref" "$digest" >/dev/null || exit 1
  node "$REPO/business/scripts/kaito-social-publish.mjs" "$ref" --digest "$digest" || exit 1
  node "$REPO/business/scripts/kaito-social-publish.mjs" "$ref" --digest "$digest" > /dev/null 2>&1; assert_eq "$?" 3 duplicate
  assert_eq "$(wc -l < "$HOME/posts" | tr -d ' ')" 1 once
  node -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1]));if(p.posts[0].value[0].content!=="Hello"||p.posts[0].value[0].image[0].id!=="media-1")process.exit(1)' "$HOME/posts" || exit 1
  grep -q 'sample media' "$HOME/upload" || exit 1
  node "$REPO/business/scripts/kaito-ledger.mjs" status "$ref" | grep -q '^state=sent$' || exit 1
  kill "$pid"; wait "$pid" 2>/dev/null || :; rm "$HOME/port"
  FAKE_DROP=1; export FAKE_DROP
  node "$REPO/tests/social-postiz-fake.mjs" & pid=$!
  i=0; while [ ! -f "$FAKE_PORT" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i+1)); done
  POSTIZ_URL="http://127.0.0.1:$(cat "$FAKE_PORT")"; export POSTIZ_URL
  out=$(node "$REPO/business/scripts/kaito-ledger.mjs" propose --owner lumen-tea --account integration-1 --action social.linkedin.publish --text-file "$HOME/post.json" --media "$HOME/media.png" --json) || exit 1
  ref=$(printf '%s' "$out" | node -pe 'JSON.parse(require("fs").readFileSync(0)).ref')
  digest=$(printf '%s' "$out" | node -pe 'JSON.parse(require("fs").readFileSync(0)).digest')
  fixture_approve "$ref" "$digest" >/dev/null || exit 1
  node "$REPO/business/scripts/kaito-social-publish.mjs" "$ref" --digest "$digest" > /dev/null 2>&1; assert_eq "$?" 1 dropped
  node "$REPO/business/scripts/kaito-ledger.mjs" status "$ref" | grep -q '^state=uncertain$' || exit 1
  node "$REPO/business/scripts/kaito-social-publish.mjs" "$ref" --digest "$digest" > /dev/null 2>&1; assert_eq "$?" 3 no-retry
  node "$REPO/business/scripts/kaito-ledger.mjs" reconcile "$ref" --failed > "$HOME/out" 2>&1
  assert_eq "$?" 3 unresolved-dispatch
  grep -q 'Postiz dispatch is unresolved' "$HOME/out" || exit 1
  node "$REPO/business/scripts/kaito-ledger.mjs" reconcile "$ref" --sent --remote-id post-1 || exit 1
  assert_eq "$(wc -l < "$HOME/posts" | tr -d ' ')" 2 no-resend
}

test_postiz_endpoint_requires_remote_https() {
  mk_home
  POSTIZ_URL='HTTP://remote.example.invalid' node "$REPO/business/scripts/kaito-engines.mjs" pick publish-social --allow-cloud --json > "$HOME/out" 2>&1
  assert_eq "$?" 4 'remote HTTP refused'
  grep -q 'remote Postiz requires HTTPS' "$HOME/out" || exit 1
}

test_postiz_consent_is_bound_to_origin() {
  mk_home
  POSTIZ_URL='HTTPS://one.example.invalid/base' node "$REPO/business/scripts/kaito-engines.mjs" consent postiz --owner lumen-tea --grant || exit 1
  POSTIZ_URL='https://one.example.invalid/other' node "$REPO/business/scripts/kaito-engines.mjs" pick publish-social --owner lumen-tea --allow-cloud --json > "$HOME/out" || exit 1
  grep -q '"path":"https://one.example.invalid/other"' "$HOME/out" || exit 1
  POSTIZ_URL='https://two.example.invalid' node "$REPO/business/scripts/kaito-engines.mjs" pick publish-social --owner lumen-tea --allow-cloud --json
  assert_eq "$?" 3 'different origin refused'
}

test_postiz_final_dispatch_requires_active_attempt_and_deadline() {
  mk_home
  mkdir -p "$KAITO_HOME/owners/lumen-tea"
  printf '%s\n' '{"id":"lumen-tea","kind":"company","channels":{"linkedin":"integration-1"}}' > "$KAITO_HOME/owners/lumen-tea/owner.json"
  printf '%s\n' '{"content":"Fixture","settings":{"__type":"linkedin"}}' > "$HOME/post.json"
  out=$(node "$REPO/business/scripts/kaito-ledger.mjs" propose --owner lumen-tea --account integration-1 --action social.linkedin.publish --text-file "$HOME/post.json" --json) || exit 1
  ref=$(printf '%s' "$out" | node -pe 'JSON.parse(require("fs").readFileSync(0)).ref')
  digest=$(printf '%s' "$out" | node -pe 'JSON.parse(require("fs").readFileSync(0)).digest')
  fixture_approve "$ref" "$digest" >/dev/null || exit 1
  node --input-type=module - "$REPO" "$ref" "$digest" <<'JS'
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
const [repo, ref, digest] = process.argv.slice(2);
const load = (file) => import(pathToFileURL(repo + '/business/' + file));
const { claimAction, recordResult } = await load('scripts/kaito-ledger.mjs');
const { openDb } = await load('scripts/kaito-ledger-lib.mjs');
const { consumeDispatch, isPostizAction, recordDispatchIntent } = await load('handlers/dispatch.mjs');
const { socialHandlers } = await load('handlers/social-publish.mjs');
const handler = socialHandlers.get('social.linkedin.publish');
await assert.rejects(handler.publish(ref, digest, 1), { code: 3 });
const db = openDb();
const { attempt } = claimAction(db, ref, digest);
const item = consumeDispatch(ref, digest, attempt, isPostizAction);
await assert.rejects(handler.publish(ref, digest, attempt), { code: 3 });
const expired = AbortSignal.abort();
assert.throws(() => recordDispatchIntent(item, () => expired.throwIfAborted()), { name: 'AbortError' });
assert.equal(db.prepare('SELECT intent_at FROM dispatch_reservations WHERE ref = ?').get(ref).intent_at, null);
recordResult(db, ref, attempt, 'uncertain');
assert.throws(() => recordDispatchIntent(item, () => {}), { code: 3 });
assert.equal(db.prepare('SELECT intent_at FROM dispatch_reservations WHERE ref = ?').get(ref).intent_at, null);
db.close();
JS
}
