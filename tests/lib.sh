#!/bin/sh
# Test helpers. Source from a *.test.sh. Never touches the real home.
TESTS_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO="$(dirname "$TESTS_DIR")"

mk_home() {
  HOME="$(mktemp -d)"
  KAITO_HOME="$HOME/.kaito"
  PATH="$TESTS_DIR/stubs:$PATH"
  export HOME KAITO_HOME PATH
  unset CODEX_HOME XDG_CONFIG_HOME KAITO_ANSWERS  # inherited values would point setup at real config
  unset TRELLO_KEY TRELLO_TOKEN
  KAITO_TRELLO_API=http://127.0.0.1:1; export KAITO_TRELLO_API  # fail closed: no test may reach real Trello
}

assert_eq() { [ "$1" = "$2" ] || { echo "  not equal: '$1' vs '$2' ($3)"; exit 1; }; }
assert_file() { [ -e "$1" ] || { echo "  missing: $1"; exit 1; }; }
assert_no() { [ ! -e "$1" ] && [ ! -L "$1" ] || { echo "  should not exist: $1"; exit 1; }; }
assert_link() {
  [ -L "$1" ] || { echo "  not a symlink: $1"; exit 1; }
  case "$(readlink "$1")" in "$2"*) ;; *) echo "  link $1 -> $(readlink "$1"), want prefix $2"; exit 1;; esac
}
