#!/bin/sh
. "$(dirname "$0")/lib.sh"

test_template_exists() {
  mk_home
  assert_file "$REPO/business/engines/twenty/compose.yml"
  grep -q 'twentycrm/twenty:' "$REPO/business/engines/twenty/compose.yml"
  grep -q '127\.0\.0\.1:' "$REPO/business/engines/twenty/compose.yml"
}
