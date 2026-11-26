#!/bin/sh
. "$(dirname "$0")/lib.sh"
test_fixture_retro() {
  mk_home
  node "$REPO/business/scripts/kaito-owner.mjs" add lumen-tea --name 'Lumen Tea' --kind company >/dev/null || exit 1
  printf '%s\n' '{"umami":{"pageviews":120,"visitors":80},"instagram":{"reach":42}}' > "$HOME/fixture.json"
  node "$REPO/business/scripts/kaito-channel-retro.mjs" --owner lumen-tea --start 2026-11-16 --end 2026-11-23 --fixture "$HOME/fixture.json" > "$HOME/retro" || exit 1
  grep -q 'pageviews: 120' "$HOME/retro" && grep -q 'reach: 42' "$HOME/retro" || exit 1
}
test_umami_pull_and_retro() {
  mk_home
  node "$REPO/business/scripts/kaito-owner.mjs" add lumen-tea --name 'Lumen Tea' --kind company >/dev/null || exit 1
  printf 'test-key\n' > "$HOME/key"
  cat > "$HOME/server.mjs" <<'SERVER'
import http from 'node:http';
import fs from 'node:fs';
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (req.headers.authorization !== 'Bearer test-key' || url.pathname !== '/api/websites/site/stats' || !url.searchParams.has('startAt') || !url.searchParams.has('endAt')) { res.writeHead(400).end(); return; }
  res.writeHead(200, {'content-type':'application/json'}).end(JSON.stringify({pageviews:{value:120},visitors:{value:80}}));
});
server.listen(0, '127.0.0.1', () => fs.writeFileSync(process.argv[2], String(server.address().port)));
SERVER
  node "$HOME/server.mjs" "$HOME/port" & pid=$!
  trap 'kill "$pid" 2>/dev/null || :' EXIT
  i=0; while [ ! -f "$HOME/port" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i+1)); done
  [ -f "$HOME/port" ] || exit 1
  base="http://127.0.0.1:$(cat "$HOME/port")/api"
  node "$REPO/business/scripts/kaito-umami.mjs" pull --owner lumen-tea --website site --start 2026-11-16 --end 2026-11-23 --url "$base" --key-file "$HOME/key" >/dev/null || exit 1
  node "$REPO/business/scripts/kaito-channel-retro.mjs" --owner lumen-tea --start 2026-11-16 --end 2026-11-23 > "$HOME/retro" || exit 1
  grep -q 'pageviews: 120' "$HOME/retro" && grep -q 'visitors: 80' "$HOME/retro" && grep -q 'No data.' "$HOME/retro" || exit 1
}

test_insights_feed_both_retros() {
  mk_home
  b="$REPO/business/scripts"
  node "$b/kaito-owner.mjs" add lumen-tea --name 'Lumen Tea' --kind company >/dev/null || exit 1
  node "$b/kaito-ledger.mjs" migrate >/dev/null || exit 1
  node --no-warnings -e '
    const { DatabaseSync } = require("node:sqlite");
    const db = new DatabaseSync(process.argv[1]);
    const add = db.prepare("INSERT INTO instagram_metrics (owner,ig_user_id,scope,subject_id,metric,period,period_end,value,snapshot_date,collected_at,graph_version) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    for (const [owner, scope, subject, day, value] of [
      ["lumen-tea", "account", "111", "2026-11-16", 23],
      ["lumen-tea", "account", "111", "2026-11-22", 42],
      ["lumen-tea", "account", "111", "2026-11-23", 100],
      ["lumen-tea", "media", "123", "2026-11-22", 25],
      ["ira-das", "account", "222", "2026-11-22", 999],
    ]) add.run(owner, subject, scope, subject, "reach", "day", "", value, day, day + "T12:00:00Z", "v27.0");
  ' "$KAITO_HOME/business/ledger.db" || exit 1
  node "$b/kaito-channel-retro.mjs" --owner lumen-tea --start 2026-11-16 --end 2026-11-23 > "$HOME/retro" || exit 1
  grep -qx -- '- reach: 42' "$HOME/retro" || exit 1
  printf '%s\n' '{"metric":"reach","target":20,"instagram":{"subject":"123","start":"2026-11-16","end":"2026-11-23"}}' > "$HOME/brief"
  node "$b/kaito-marketing.mjs" retro --owner lumen-tea --brief "$HOME/brief" > "$HOME/retro" || exit 1
  grep -q 'reach: 25; target: 20' "$HOME/retro"
}
