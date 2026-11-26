#!/bin/sh
. "$(dirname "$0")/lib.sh"
C="$REPO/business/scripts/kaito-claims.mjs"
test_claims_require_current_owner_evidence() {
  mk_home
  node "$REPO/business/scripts/kaito-owner.mjs" add lumen-tea --name 'Lumen Tea Co.' --kind company >/dev/null
  printf '%s\n' 'Discover the healthiest tea in India.' > "$HOME/post.txt"
  node "$C" check --owner lumen-tea "$HOME/post.txt" > "$HOME/out" 2>&1; rc=$?
  assert_eq "$rc" 1 unsourced
  grep -q ':1' "$HOME/out" || exit 1
  printf '%s\n' '[{"claim":"the healthiest tea in India","source":"fixture study","date":"2026-01-01","expiry":"2999-01-01"}]' > "$KAITO_HOME/owners/lumen-tea/evidence.json"
  node "$C" check --owner lumen-tea "$HOME/post.txt" > "$HOME/out" 2>&1; assert_eq "$?" 0 sourced
  sed 's/2999-01-01/2000-01-01/' "$KAITO_HOME/owners/lumen-tea/evidence.json" > "$HOME/expired"; cp "$HOME/expired" "$KAITO_HOME/owners/lumen-tea/evidence.json"
  node "$C" check --owner lumen-tea "$HOME/post.txt" > "$HOME/out" 2>&1; assert_eq "$?" 1 expired
}

test_review_and_retro() {
  mk_home
  node "$REPO/business/scripts/kaito-owner.mjs" add lumen-tea --name 'Lumen Tea Co.' --kind company >/dev/null
  printf '%s\n' '{"buyer":"tea drinkers","message":"taste Darjeeling","action":"visit the shop","metric":"clicks","target":10}' > "$HOME/brief.json"
  printf '%s\n' 'A completely unrelated post.' > "$HOME/post.txt"
  node "$REPO/business/scripts/kaito-marketing.mjs" review --owner lumen-tea --brief "$HOME/brief.json" --post "$HOME/post.txt" > "$HOME/out" 2>&1; assert_eq "$?" 1 off-brief
  grep -q 'FAIL' "$HOME/out" || exit 1
  printf '%s\n' '{"clicks":12}' > "$HOME/metrics.json"
  node "$REPO/business/scripts/kaito-marketing.mjs" retro --owner lumen-tea --brief "$HOME/brief.json" --metrics "$HOME/metrics.json" > "$HOME/out" 2>&1; assert_eq "$?" 0 retro
  grep -q '12' "$HOME/out" || exit 1
}
