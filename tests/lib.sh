#!/bin/sh
# Test helpers. Source from a *.test.sh. Never touches the real home.
TESTS_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO="$(dirname "$TESTS_DIR")"
IS_WIN=0
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) IS_WIN=1 ;; esac
# Fixtures made with ln -s must be real symlinks on Windows, not Git Bash's default copies.
[ "$IS_WIN" = 0 ] || { MSYS="${MSYS:-} winsymlinks:native"; export MSYS; }
# JSON arguments to node keep their /paths (setup sets the same).
[ "$IS_WIN" = 0 ] || { MSYS2_ARG_CONV_EXCL='";[;{'; export MSYS2_ARG_CONV_EXCL; }
# skip_on_win "<why>": end this test early on Windows, with the reason in the log.
skip_on_win() { [ "$IS_WIN" = 1 ] || return 1; echo "skip: $1 (Windows)"; }

mk_home() {
  HOME="$(mktemp -d)"
  KAITO_HOME="$HOME/.kaito"
  PATH="$TESTS_DIR/stubs:$PATH"
  export HOME KAITO_HOME PATH
  unset CODEX_HOME XDG_CONFIG_HOME KAITO_ANSWERS  # inherited values would point setup at real config
  unset TRELLO_KEY TRELLO_TOKEN PLANE_API_KEY PLANE_WORKSPACE PLANE_BASE_URL KAITO_TASKS_MANAGER KAITO_PLANE_PAGES
  unset LINEAR_API_KEY KAITO_LINEAR_PAGES
  KAITO_TRELLO_API=http://127.0.0.1:1; export KAITO_TRELLO_API  # fail closed: no test may reach real Trello
  KAITO_PLANE_API=http://127.0.0.1:1; export KAITO_PLANE_API    # nor real Plane
  KAITO_LINEAR_API=http://127.0.0.1:1; export KAITO_LINEAR_API  # nor real Linear
}

assert_eq() { [ "$1" = "$2" ] || { echo "  not equal: '$1' vs '$2' ($3)"; exit 1; }; }
assert_file() { [ -e "$1" ] || { echo "  missing: $1"; exit 1; }; }
assert_no() { [ ! -e "$1" ] && [ ! -L "$1" ] || { echo "  should not exist: $1"; exit 1; }; }
assert_link() {
  [ -L "$1" ] || { echo "  not a symlink: $1"; exit 1; }
  case "$(readlink "$1")" in "$2"*) ;; *) echo "  link $1 -> $(readlink "$1"), want prefix $2"; exit 1;; esac
}
