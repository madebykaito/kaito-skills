#!/bin/sh
. "$(dirname "$0")/lib.sh"
B="$REPO/business/scripts"
pub() { node "$B/kaito-instagram-publish.mjs" "$@"; }
ins() { node "$B/kaito-instagram-insights.mjs" "$@"; }
ledger() { node "$B/kaito-ledger.mjs" "$@"; }
jget() { node -e 'console.log(JSON.parse(require("fs").readFileSync(0))[process.argv[1]])' "$1"; }
expect() {
  want=$1; shift
  got=0
  "$@" > "$HOME/out" 2>&1 || got=$?
  [ "$want" = "$got" ] || { cat "$HOME/out"; echo "exit $got, expected $want"; exit 1; }
}
fixture() {
  mk_home
  mkdir -p "$KAITO_HOME/owners/lumen-tea"
  O="$KAITO_HOME/owners/lumen-tea"
  cd "$HOME" || exit 1
  printf '{"id":"lumen-tea","name":"Lumen Tea Co.","kind":"company","channels":{"instagram":"@lumentea.example"},"keys":{"instagram":"%s/key.json"}}\n' "$HOME" > "$O/owner.json"
  : > "$HOME/mode"
  node "$TESTS_DIR/fixtures/instagram/graph.mjs" "$HOME" > "$HOME/server.log" 2>&1 &
  PID=$!
  trap 'kill "$PID" 2>/dev/null || :; wait "$PID" 2>/dev/null || :; cat "$HOME/server.log"' EXIT
  n=0
  until [ -s "$HOME/port" ]; do
    n=$((n + 1)); [ "$n" -le 50 ] || exit 1
    sleep .1
  done
  API="http://127.0.0.1:$(cat "$HOME/port")"
  export KAITO_INSTAGRAM_POLL_MS=10
  # JPEG marker and payload are sufficient for the fake Graph server.
  printf '\377\330\377fixture' > "$HOME/photo.jpg"
  printf '\377\330\377cover' > "$HOME/cover.jpg"
  printf 'First flush from Darjeeling.\r\n' > "$HOME/caption"
  printf '{"cloud":{"instagram-graph":{"granted":true}}}\n' > "$O/consent.json"
}
key() {
  TARGET=$(node -e '
    const [base, ...files] = process.argv.slice(1);
    const objects = Object.fromEntries(files.map((file, i) => {
      const sha = require("crypto").createHash("sha256").update(require("fs").readFileSync(file)).digest("hex");
      return [sha, { put_url: base + "/upload/" + i, read_url: base + "/public/" + i }];
    }));
    console.log(JSON.stringify({ kind: "presigned-put", objects }));
  ' "$API" "$@") || exit 1
  umask 077
  printf '{"access_token":"fixture-token","ig_user_id":"111","graph_url":"%s","upload":%s}\n' "$API" "$TARGET" > "$HOME/key.json"
}
proposal() {
  result=$(pub propose "$@" --owner lumen-tea --json) || exit 1
  REF=$(printf '%s' "$result" | jget ref)
  DIG=$(printf '%s' "$result" | jget digest)
}
approve_fixture() {
  # This mirrors the isolated, synthetic host approval in ledger.test.sh.
  fixture_approve "$REF" "$DIG" > "$HOME/approval" || exit 1
}
state() { ledger status "$REF" --json | jget state; }
remote() { ledger status "$REF" --json | jget remote_id; }
publishes() { awk '/"path":"\/v27.0\/111\/media_publish"/{n++} END{print n+0}' "$HOME/requests"; }
make_reel() {
  ffmpeg -nostdin -loglevel error -f lavfi -i color=s=64x96:r=25 -f lavfi -i "sine=sample_rate=$1" \
    -t 3.2 -c:v libx264 -threads 1 -c:a aac -movflags "$2" -y "$3" || exit 1
}

test_reel_publish_concurrent_retry_once() {
  command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || { echo 'skip: ffmpeg or ffprobe missing'; return 0; }
  fixture
  make_reel 48000 +faststart "$HOME/reel.mp4"
  key "$HOME/reel.mp4" "$HOME/cover.jpg"
  proposal reel --media "$HOME/reel.mp4" --caption-file "$HOME/caption" --cover "$HOME/cover.jpg" \
    --location-id 123 --collaborator @ira.example --disclosure ai
  expect 3 pub publish "$REF" --digest "$DIG"
  assert_no "$HOME/requests"
  approve_fixture
  printf 'edited draft' > "$HOME/caption"
  pub publish "$REF" --digest "$DIG" > "$HOME/first" 2>&1 & one=$!
  pub publish "$REF" --digest "$DIG" > "$HOME/second" 2>&1 & two=$!
  first=0; second=0
  wait "$one" || first=$?
  wait "$two" || second=$?
  case "$first:$second" in 0:3|3:0) ;; *) cat "$HOME/first" "$HOME/second"; exit 1 ;; esac
  expect 3 pub publish "$REF" --digest "$DIG"
  assert_eq "$(publishes)" 1 one-publish
  assert_eq "$(state)" sent recorded
  [ "$(remote)" -gt 200 ] || exit 1
  node -e '
    const a = require("fs").readFileSync(process.argv[1], "utf8").trim().split("\n").map(JSON.parse);
    const p = a.find(r => r.params.media_type === "REELS").params;
    const s = require("assert/strict");
    s.equal(p.caption, "First flush from Darjeeling.\n");
    s.equal(p.is_ai_generated, true);
    s.equal(p.location_id, "123");
    s.deepEqual(p.collaborators, ["ira.example"]);
    s.ok(p.cover_url && p.video_url);
    s.ok(a.filter(r => r.params.fields === "status_code").length >= 2);
  ' "$HOME/requests" || exit 1
}

test_scheduled_carousel_image_and_story() {
  fixture
  key "$HOME/photo.jpg" "$HOME/cover.jpg"
  proposal carousel --media "$HOME/photo.jpg" "$HOME/cover.jpg" --caption-file "$HOME/caption" --due 2099-11-26T06:30:00Z
  approve_fixture
  expect 3 pub publish "$REF" --digest "$DIG"
  assert_no "$HOME/requests"
  proposal carousel --media "$HOME/photo.jpg" "$HOME/cover.jpg" --caption-file "$HOME/caption" --due "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  approve_fixture
  if [ -f "$B/kaito-tick.mjs" ]; then
    node "$B/kaito-tick.mjs" > "$HOME/handler" 2>&1 || { cat "$HOME/handler"; exit 1; }
  else
    node "$TESTS_DIR/fixtures/instagram/scheduler.mjs" "$REPO" "$REF" > "$HOME/handler" 2>&1 || { cat "$HOME/handler"; exit 1; }
  fi
  assert_eq "$(state)" sent carousel
  proposal story --media "$HOME/photo.jpg" --disclosure ai
  approve_fixture
  expect 0 pub publish "$REF" --digest "$DIG"
  assert_eq "$(state)" sent story
  proposal image --media "$HOME/photo.jpg"
  approve_fixture
  expect 0 pub publish "$REF" --digest "$DIG"
  assert_eq "$(state)" sent image
  assert_eq "$(publishes)" 3 scheduled-and-immediate
}

test_lost_response_reconcile_and_insights() {
  fixture
  key "$HOME/photo.jpg"
  proposal image --media "$HOME/photo.jpg" --caption-file "$HOME/caption"
  approve_fixture
  echo lose > "$HOME/mode"
  expect 3 pub publish "$REF" --digest "$DIG"
  assert_eq "$(state)" uncertain lost-response
  expect 3 pub publish "$REF" --digest "$DIG"
  assert_eq "$(publishes)" 1 no-resend
  expect 0 pub reconcile "$REF"
  assert_eq "$(state)" reconciled matched
  expect 0 ins daily --owner lumen-tea --json
  assert_eq "$(jget skipped < "$HOME/out")" 1 prior-business-conversion
  expect 0 ins pull --owner lumen-tea --json
  expect 0 ins list --owner lumen-tea --json
  node -e '
    const x = JSON.parse(require("fs").readFileSync(0));
    const a = require("assert/strict"), id = process.argv[1];
    a.ok(x.some(m => m.scope === "account" && m.metric === "reach" && m.value === 12));
    a.ok(x.some(m => m.scope === "account" && m.metric === "views" && m.value === 23));
    a.ok(x.some(m => m.scope === "media" && m.subject_id === id && m.metric === "views" && m.value === 7));
    a.ok(x.every(m => m.subject_id !== "951"));
    a.equal(x.length, new Set(x.map(m => [m.scope, m.subject_id, m.metric, m.snapshot_date, m.period_end].join())).size);
  ' "$(remote)" < "$HOME/out" || exit 1
  expect 0 ins daily --owner lumen-tea --json
  assert_eq "$(jget status < "$HOME/out")" current daily-idempotent
}

test_reel_96khz_rejected_before_upload() {
  command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || { echo 'skip: ffmpeg or ffprobe missing'; return 0; }
  fixture
  make_reel 96000 +faststart "$HOME/reel.mp4"
  key "$HOME/reel.mp4"
  expect 2 pub preflight "$HOME/reel.mp4"
  grep -q '48 kHz' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  expect 2 pub propose reel --owner lumen-tea --media "$HOME/reel.mp4"
  assert_no "$HOME/requests"
  make_reel 48000 -faststart "$HOME/reel.mp4"
  expect 2 pub preflight "$HOME/reel.mp4"
  grep -q 'moov' "$HOME/out" || { cat "$HOME/out"; exit 1; }
}

test_reel_scheduled_prepare_does_not_publish() {
  command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || { echo 'skip: ffmpeg or ffprobe missing'; return 0; }
  fixture
  make_reel 48000 +faststart "$HOME/reel.mp4"
  key "$HOME/reel.mp4"
  due_soon=$(node -p 'new Date(Date.now() + 5 * 60_000).toISOString().replace(/\.\d{3}Z$/, "Z")')
  proposal reel --media "$HOME/reel.mp4" --thumb-offset 500 --due "$due_soon"
  approve_fixture
  if [ -f "$B/kaito-tick.mjs" ]; then
    node "$B/kaito-tick.mjs" || exit 1
  else
    node "$TESTS_DIR/fixtures/instagram/scheduler.mjs" "$REPO" "$REF" only || exit 1
  fi
  assert_eq "$(publishes)" 0 prepared-only
  grep -q '"thumb_offset":500' "$HOME/requests" || exit 1
  proposal reel --media "$HOME/reel.mp4" --thumb-offset 500 --due "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  approve_fixture
  node "$TESTS_DIR/fixtures/instagram/scheduler.mjs" "$REPO" "$REF" prepare || exit 1
  assert_eq "$(publishes)" 1 used-prepared-container
  grep -q '"creation_id":"202"' "$HOME/requests" || exit 1
  assert_eq "$(awk '/"method":"POST","path":"\/v27.0\/111\/media"/{n++} END{print n+0}' "$HOME/requests")" 2 one-container-per-ref
  assert_eq "$(state)" sent scheduled-reel
}

test_tunnel_refusal_then_new_approval() {
  fixture
  mkdir "$HOME/tunnel"
  chmod 700 "$HOME/tunnel"
  printf '{"access_token":"fixture-token","ig_user_id":"111","graph_url":"%s","upload":{"kind":"tunnel","base_url":"%s/tunnel","directory":"%s/tunnel"}}\n' \
    "$API" "$API" "$HOME" > "$HOME/key.json"
  proposal image --media "$HOME/photo.jpg"
  approve_fixture
  echo refuse > "$HOME/mode"
  expect 1 pub publish "$REF" --digest "$DIG"
  assert_eq "$(state)" failed definitive
  if grep -q 'fixture-token' "$HOME/out"; then exit 1; fi
  expect 3 pub publish "$REF" --digest "$DIG"
  proposal image --media "$HOME/photo.jpg" --retry-of "$REF"
  approve_fixture
  : > "$HOME/mode"
  expect 0 pub publish "$REF" --digest "$DIG"
  assert_eq "$(state)" sent retried
  assert_eq "$(publishes)" 2 one-refusal-one-acceptance
  assert_eq "$(ls -A "$HOME/tunnel")" "" staged-media-removed
}

test_misconfigured_upload_cannot_publish_other_bytes() {
  fixture
  key "$HOME/photo.jpg"
  proposal image --media "$HOME/photo.jpg"
  approve_fixture
  echo wrong-bytes > "$HOME/mode"
  expect 1 pub publish "$REF" --digest "$DIG"
  grep -q 'differ from the approved media' "$HOME/out" || exit 1
  if grep -q '"method":"POST"' "$HOME/requests"; then exit 1; fi
  assert_eq "$(state)" failed wrong-upload
}

test_scheduler_pulls_insights_once_per_day() {
  fixture
  key "$HOME/photo.jpg"
  mkdir -p "$KAITO_HOME/business"
  printf '%s\n' '["lumen-tea"]' > "$KAITO_HOME/business/instagram-insights.json"
  node "$B/kaito-tick.mjs" > "$HOME/first" || exit 1
  grep -q '^instagram-insights=lumen-tea' "$HOME/first" || exit 1
  cp "$HOME/requests" "$HOME/requests-first"
  node "$B/kaito-tick.mjs" > "$HOME/second" || exit 1
  assert_eq "$(cat "$HOME/second")" "" no-second-pull
  cmp "$HOME/requests" "$HOME/requests-first"
}
