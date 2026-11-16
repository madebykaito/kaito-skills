#!/bin/sh
# Runs every tests/*.test.sh in its own shell. Each defines test_* functions.
here="$(cd "$(dirname "$0")" && pwd -P)"
fail=0
for t in "$here"/*.test.sh; do
  name=$(basename "$t" .test.sh)
  if sh -c '. "$0"; for f in $(sed -n "s/^\(test_[a-z0-9_]*\)().*/\1/p" "$0"); do ( "$f" ) || exit 1; done' "$t"; then
    echo "PASS $name"
  else
    echo "FAIL $name"; fail=1
  fi
done
exit $fail
