#!/bin/sh
. "$(dirname "$0")/lib.sh"
CG="$REPO/helpmekaito/scripts/kaito-codegraph.sh"
PIN=$(cat "$REPO/codegraph.version")

mk_repo() {
  R="$(mktemp -d)/kaito-skills"
  node "$REPO/helpmekaito/scripts/kaito-sync.mjs" mirror -x .git -x .codegraph -x ./gstack -x ./.superpowers -x node_modules "$REPO" "$R"
}
run_setup() { "$R/setup" --no-gstack "$@" > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }; }
GI() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"; }
proj() { P="$(mktemp -d)/$1"; mkdir -p "$P"; P=$(cd "$P" && pwd -P); }

test_codegraph_pinned_install() {
  mk_home; mk_repo; run_setup --yes
  grep -qx "npm i -g @colbymchenry/codegraph@$PIN" "$HOME/stub.log" || { cat "$HOME/stub.log"; exit 1; }
  grep -qx 'codegraph install --target claude,codex --location global -y' "$HOME/stub.log" || exit 1
}

test_codegraph_declined() {
  mk_home; mk_repo; KAITO_ANSWERS=codegraph=n,gitignore=n run_setup --yes
  ! grep -q '^npm' "$HOME/stub.log" 2>/dev/null || exit 1
  assert_no "$(GI)"
}

test_no_codegraph_flag() {
  mk_home; mk_repo; run_setup --yes --no-codegraph
  assert_no "$HOME/stub.log"
  assert_no "$(GI)"
}

test_codegraph_skip_when_current() {
  mk_home; mk_repo; CODEGRAPH_STUB_VERSION=$PIN run_setup --yes
  ! grep -q '^npm' "$HOME/stub.log" || exit 1
  CODEGRAPH_STUB_VERSION=$PIN run_setup --yes
  assert_eq "$(grep -c '^codegraph install' "$HOME/stub.log")" 1 connected_once
}

test_gitignore_once() {
  mk_home; mk_repo; run_setup --yes; run_setup --yes
  assert_eq "$(grep -cx '\.codegraph' "$(GI)")" 1 once
}

test_gitignore_honors_xdg() {
  mk_home; mk_repo; XDG_CONFIG_HOME="$HOME/xdg" run_setup --yes
  assert_eq "$(cat "$HOME/xdg/git/ignore")" .codegraph xdg
}

test_slug_stable() {
  mk_home; proj app; a=$P; proj app; b=$P
  assert_eq "$(sh "$CG" slug "$a")" "$(sh "$CG" slug "$a")" same
  [ "$(sh "$CG" slug "$a")" != "$(sh "$CG" slug "$b")" ] || exit 1
  case "$(sh "$CG" slug "$a")" in app-????????) ;; *) echo bad slug; exit 1 ;; esac
}

test_init_links_central() {
  mk_home; proj app
  sh "$CG" init "$P" >/dev/null
  s=$(sh "$CG" slug "$P")
  assert_link "$P/.codegraph" "$KAITO_HOME/codegraph/$s"
  assert_eq "$(cat "$KAITO_HOME/codegraph/$s/.kaito-path")" "$P" path
  grep -q '^codegraph init -y' "$HOME/stub.log" || exit 1
  sh "$CG" status | grep -q "^$s $P " || exit 1
}

test_init_refuses_real_folder() {
  mk_home; proj app; mkdir "$P/.codegraph"
  ! sh "$CG" init "$P" 2>/dev/null || exit 1
  [ ! -L "$P/.codegraph" ] || exit 1
}

test_refuses_home() {
  mk_home
  ! sh "$CG" init "$HOME" 2>/dev/null || exit 1
  ! sh "$CG" adopt "$HOME" 2>/dev/null || exit 1
  ! sh "$CG" init / 2>/dev/null || exit 1
  assert_no "$KAITO_HOME/codegraph"
}

test_adopt_moves_existing() {
  mk_home; proj app; mkdir "$P/.codegraph"; echo db > "$P/.codegraph/graph.db"
  sh "$CG" adopt "$P" >/dev/null
  s=$(sh "$CG" slug "$P")
  assert_link "$P/.codegraph" "$KAITO_HOME/codegraph/$s"
  assert_eq "$(cat "$P/.codegraph/graph.db")" db moved
  sh "$CG" adopt "$P" >/dev/null   # no-op
  assert_eq "$(cat "$KAITO_HOME/codegraph/$s/graph.db")" db still
}

test_no_tty_uses_defaults() {
  skip_on_win "no setsid to drop the terminal" && return 0
  mk_home; mk_repo
  SH=sh; [ -x /bin/dash ] && SH=/bin/dash   # dash exits on a failed redirect of a special builtin
  python3 -c 'import os,sys;os.setsid();os.execvp(sys.argv[1],sys.argv[1:])' "$SH" "$R/setup" --no-gstack </dev/null >"$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }
  grep -q '^kaito:' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  ! grep -q 'Device not configured' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  grep -qx "npm i -g @colbymchenry/codegraph@$PIN" "$HOME/stub.log" || exit 1
  assert_eq "$(cat "$(GI)")" .codegraph default
}

test_answers_are_keyed() {
  mk_home; mk_repo; KAITO_ANSWERS=gitignore=n run_setup --yes
  grep -qx "npm i -g @colbymchenry/codegraph@$PIN" "$HOME/stub.log" || exit 1
  assert_no "$(GI)"
}

test_adopt_recovers_after_interrupt() {
  mk_home; proj app; s=$(sh "$CG" slug "$P")
  mkdir -p "$KAITO_HOME/codegraph/$s"; echo db > "$KAITO_HOME/codegraph/$s/x"  # moved, never linked
  sh "$CG" adopt "$P" >/dev/null || exit 1
  assert_link "$P/.codegraph" "$KAITO_HOME/codegraph/$s"
}

test_failed_init_keeps_existing_index() {
  mk_home; proj app; s=$(sh "$CG" slug "$P")
  mkdir -p "$KAITO_HOME/codegraph/$s"; echo db > "$KAITO_HOME/codegraph/$s/x"
  CODEGRAPH_STUB_FAIL=1 sh "$CG" init "$P" >/dev/null 2>&1 && exit 1
  assert_file "$KAITO_HOME/codegraph/$s/x"
  proj fresh; s=$(sh "$CG" slug "$P")
  CODEGRAPH_STUB_FAIL=1 sh "$CG" init "$P" >/dev/null 2>&1 && exit 1
  assert_no "$P/.codegraph"; assert_no "$KAITO_HOME/codegraph/$s"
}
