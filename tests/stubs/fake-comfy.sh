#!/bin/sh
# Helpers for tests that need a ComfyUI. Source after lib.sh and mk_home.
# start_fake [fake_comfy.py options]  sets COMFY_URL and FAKELOG; the server stops when the test shell exits.
# Tests never touch the real heavy-model lock: it points into the temp home.
have_py() { command -v python3 >/dev/null 2>&1 || { echo "skip: python3 is not installed"; return 1; }; }

comfy_env() {
  KAITO_HEAVY_LOCK="$HOME/heavy.lock"; export KAITO_HEAVY_LOCK
  KAITO_LOCK_POLL=0.2; export KAITO_LOCK_POLL
  unset COMFY_URL COMFY_NEED_GB
}

start_fake() {
  comfy_env
  FAKELOG="$HOME/fake.log"; : > "$FAKELOG"
  _pf="$HOME/fake.port"; rm -f "$_pf"
  python3 "$TESTS_DIR/stubs/fake_comfy.py" --port-file "$_pf" --log "$FAKELOG" "$@" > "$HOME/fake.out" 2>&1 &
  FAKEPID=$!
  trap 'kill "$FAKEPID" 2>/dev/null || :; wait "$FAKEPID" 2>/dev/null || :' EXIT
  wait_for_server "$_pf" "$FAKEPID" 'fake ComfyUI' "$HOME/fake.out"
  COMFY_URL="http://127.0.0.1:$(cat "$_pf")"; export COMFY_URL
}

# line number of the first (or last) log line with this path; empty when none
log_first() { grep -n "\"p\": \"$1\"" "$FAKELOG" | head -1 | cut -d: -f1; }
log_last() { grep -n "\"p\": \"$1\"" "$FAKELOG" | tail -1 | cut -d: -f1; }
log_count() { grep -c "\"p\": \"$1\"" "$FAKELOG" || true; }
