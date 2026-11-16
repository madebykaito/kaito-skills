#!/bin/sh
. "$(dirname "$0")/lib.sh"
CG="$REPO/helpmekaito/scripts/kaito-codegraph.sh"

mk_repo() {
  R="$(mktemp -d)/kaito-skills"
  rsync -a --exclude .git --exclude /gstack/ --exclude /.superpowers/ --exclude node_modules "$REPO/" "$R/"
}
run_setup() { "$R/setup" --no-gstack "$@" > "$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }; }
GI() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"; }
proj() { P="$(mktemp -d)/$1"; mkdir -p "$P"; P=$(cd "$P" && pwd -P); }

test_codegraph_pinned_install() {
  mk_home; mk_repo; run_setup --yes
  grep -qx 'npm i -g @colbymchenry/codegraph@1.6.2' "$HOME/stub.log" || { cat "$HOME/stub.log"; exit 1; }
  grep -qx 'codegraph install --target claude,codex --location global -y' "$HOME/stub.log" || exit 1
}

test_codegraph_declined() {
  mk_home; mk_repo; KAITO_ANSWERS=n,n run_setup --yes
  ! grep -q '^npm' "$HOME/stub.log" 2>/dev/null || exit 1
  assert_no "$(GI)"
}

test_no_codegraph_flag() {
  mk_home; mk_repo; run_setup --yes --no-codegraph
  assert_no "$HOME/stub.log"
  assert_no "$(GI)"
}

test_codegraph_skip_when_current() {
  mk_home; mk_repo; CODEGRAPH_STUB_VERSION=1.6.2 run_setup --yes
  ! grep -q '^npm' "$HOME/stub.log" || exit 1
  ! grep -q '^codegraph install' "$HOME/stub.log" || exit 1
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
  mk_home; mk_repo
  python3 -c 'import os,sys;os.setsid();os.execv(sys.argv[1],sys.argv[1:])' "$R/setup" --no-gstack </dev/null >"$HOME/out" 2>&1 || { cat "$HOME/out"; exit 1; }
  grep -q '^kaito:' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  ! grep -q 'Device not configured' "$HOME/out" || { cat "$HOME/out"; exit 1; }
  grep -qx 'npm i -g @colbymchenry/codegraph@1.6.2' "$HOME/stub.log" || exit 1
  assert_eq "$(cat "$(GI)")" .codegraph default
}
