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
  node --no-warnings -e 'const {DatabaseSync}=require("node:sqlite");const db=new DatabaseSync(process.argv[1]);db.prepare("INSERT INTO approvals(ref,digest,via,at) VALUES(?,?,?,?)").run(process.argv[2],process.argv[3],"terminal",new Date().toISOString());db.prepare("UPDATE actions SET state = ? WHERE ref = ?").run("approved",process.argv[2])' "$KAITO_HOME/business/ledger.db" "$ref" "$digest" || exit 1
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
  node --no-warnings -e 'const {DatabaseSync}=require("node:sqlite");const db=new DatabaseSync(process.argv[1]);db.prepare("INSERT INTO approvals(ref,digest,via,at) VALUES(?,?,?,?)").run(process.argv[2],process.argv[3],"terminal",new Date().toISOString());db.prepare("UPDATE actions SET state = ? WHERE ref = ?").run("approved",process.argv[2])' "$KAITO_HOME/business/ledger.db" "$ref" "$digest" || exit 1
  node "$REPO/business/scripts/kaito-social-publish.mjs" "$ref" --digest "$digest" > /dev/null 2>&1; assert_eq "$?" 1 dropped
  node "$REPO/business/scripts/kaito-ledger.mjs" status "$ref" | grep -q '^state=uncertain$' || exit 1
  node "$REPO/business/scripts/kaito-social-publish.mjs" "$ref" --digest "$digest" > /dev/null 2>&1; assert_eq "$?" 3 no-retry
  assert_eq "$(wc -l < "$HOME/posts" | tr -d ' ')" 2 no-resend
}
