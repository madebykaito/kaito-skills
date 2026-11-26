#!/bin/sh
. "$(dirname "$0")/lib.sh"

test_twenty_round_trip() {
  mk_home
  node "$TESTS_DIR/fixtures/business/twenty-round-trip.mjs" "$REPO" "$HOME"
}
