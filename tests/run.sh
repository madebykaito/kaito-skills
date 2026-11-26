#!/bin/sh
# Runs every test_* in tests/*.test.sh (or only the files given), each in its own shell,
# KAITO_TEST_JOBS at a time (default 8). Tests are independent: each makes its own temp home.
here="$(cd "$(dirname "$0")" && pwd -P)"
[ $# -gt 0 ] || set -- "$here"/*.test.sh

# Some endpoint scanners hold every launch of the installed node for 0.5-3s; a private copy
# starts in milliseconds. Test runs only; falls back to the normal node. KAITO_TEST_NODE_COPY=0 turns it off.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) KAITO_TEST_NODE_COPY=0 ;; esac  # node.exe without .exe will not start
if [ "${KAITO_TEST_NODE_COPY:-1}" != 0 ] && n=$(command -v node) && v=$(node -v 2>/dev/null); then
  d=${TMPDIR:-/tmp}; d="${d%/}/kaito-test-node-$v"
  if [ ! -x "$d/node" ]; then mkdir -p "$d" && cp "$n" "$d/node.$$" && mv "$d/node.$$" "$d/node"; fi
  if [ "$("$d/node" -v 2>/dev/null)" = "$v" ]; then PATH="$d:$PATH"; export PATH; fi
fi

# Every temp folder a test makes (homes, repo copies) lands in one run folder, removed at the end.
tmp=${TMPDIR:-/tmp}; run=$(mktemp -d "${tmp%/}/kaito-tests.XXXXXX")
trap 'rm -rf "$run"' EXIT
trap 'exit 130' INT TERM
logs="$run/logs"; mkdir "$logs"
# macOS mktemp ignores TMPDIR, so a wrapper puts template-less calls in the run folder.
mkdir "$run/bin"
real=$(command -v mktemp)
cat > "$run/bin/mktemp" <<EOF
#!/bin/sh
for a in "\$@"; do case "\$a" in -*) ;; *) exec "$real" "\$@" ;; esac; done
exec "$real" "\$@" "$run/tmp.XXXXXXXXXX"
EOF
chmod +x "$run/bin/mktemp"
TMPDIR="$run"; PATH="$run/bin:$PATH"; export TMPDIR PATH
for t in "$@"; do
  t=$(cd "$(dirname "$t")" && pwd -P)/$(basename "$t")
  sed -n 's/^\(test_[a-z0-9_]*\)().*/\1/p' "$t" | sed "s|^|$t |"
done | KAITO_TEST_LOGS=$logs xargs -P "${KAITO_TEST_JOBS:-8}" -n 2 sh -c '
  # $0 = test file (tests find lib.sh through it), $1 = test name
  # BusyBox xargs shares its input pipe with workers. Tests must not read job names.
  exec </dev/null
  . "$0"; log="$KAITO_TEST_LOGS/$(basename "$0" .test.sh).$1"
  if ( "$1" ) > "$log" 2>&1; then : > "$log.ok"
  else echo "FAIL $(basename "$0" .test.sh) $1"; sed "s/^/    /" "$log" | tail -n 15; fi'
fail=0
for t in "$@"; do
  name=$(basename "$t" .test.sh)
  total=$(sed -n 's/^\(test_[a-z0-9_]*\)().*/\1/p' "$t" | wc -l | tr -d ' ')
  ok=$(ls "$logs" | grep -c "^$name\..*\.ok$" | tr -d ' ')
  if [ "$ok" = "$total" ]; then echo "PASS $name ($ok)"; else echo "FAIL $name ($ok/$total)"; fail=1; fi
done
exit $fail
