#!/bin/sh
. "$(dirname "$0")/lib.sh"
OB="$REPO/helpmekaito/scripts/kaito-obsidian.sh"
JS="$REPO/helpmekaito/scripts/kaito-json.mjs"

# stub <status>: starts the fake API, sets URL, REC, SPID
stub() {
  REC="$HOME/rec.jsonl"; : > "$REC"
  node "$TESTS_DIR/stubs/obsidian-api.mjs" "$REC" "${1:-204}" "$HOME/port" & SPID=$!
  i=0; while [ ! -s "$HOME/port" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  URL="http://127.0.0.1:$(cat "$HOME/port")"
}
# setup <api_url>: enabled config, key, and a note
setup() {
  mkdir -p "$KAITO_HOME/memory/projects"
  printf '{"obsidian":{"enabled":true,"vault_path":"%s","api_url":"%s"}}\n' "${2:-madebykaito/helpmekaito}" "$1" > "$KAITO_HOME/config.json"
  printf 'OTHER=1\nOBSIDIAN_API_KEY=sekrit-key-123\n' > "$KAITO_HOME/.env"
  echo "- hello" > "$KAITO_HOME/memory/global.md"
  echo "- idx" > "$KAITO_HOME/memory/MEMORY.md"
  echo "- p" > "$KAITO_HOME/memory/projects/app.md"
}

test_obsidian_disabled_noop() {
  mk_home; stub; setup "$URL"
  node "$JS" set "$KAITO_HOME/config.json" obsidian.enabled false
  out=$(sh "$OB" push global.md); rc=$?
  kill $SPID
  assert_eq "$rc" 0 rc
  case "$out" in "obsidian mirror skipped: "*) ;; *) echo "$out"; exit 1;; esac
  assert_eq "$(wc -l < "$REC" | tr -d ' ')" 0 requests
}

test_obsidian_put_path_and_auth() {
  mk_home; stub; setup "$URL"
  sh "$OB" push global.md; kill $SPID
  r=$(cat "$REC")
  assert_eq "$(printf "%s\n" "$r" | node -pe 'const j=JSON.parse(require("fs").readFileSync(0));j.method+" "+j.path')" "PUT /vault/madebykaito/helpmekaito/Global.md" req
  assert_eq "$(printf "%s\n" "$r" | node -pe 'JSON.parse(require("fs").readFileSync(0)).headers.authorization')" "Bearer sekrit-key-123" auth
  assert_eq "$(printf "%s\n" "$r" | node -pe 'JSON.parse(require("fs").readFileSync(0)).headers["content-type"]')" "text/markdown" ctype
  assert_eq "$(printf "%s\n" "$r" | node -pe 'JSON.parse(require("fs").readFileSync(0)).body')" "- hello" body
}

test_mapping_names() {
  mk_home; stub; setup "$URL" "my vault/x"
  sh "$OB" push MEMORY.md; sh "$OB" push projects/app.md; kill $SPID
  paths=$(node -pe 'require("fs").readFileSync(process.argv[1],"utf8").trim().split("\n").map(l=>JSON.parse(l).path).join(" ")' "$REC")
  assert_eq "$paths" "/vault/my%20vault/x/Memory.md /vault/my%20vault/x/projects/app.md" paths
}

test_unknown_note_skipped() {
  mk_home; stub; setup "$URL"
  out=$(sh "$OB" push other.md); rc=$?; kill $SPID
  assert_eq "$rc" 0 rc
  assert_eq "$out" "obsidian mirror skipped: unknown note other.md" msg
  assert_eq "$(wc -l < "$REC" | tr -d ' ')" 0 requests
}

test_obsidian_api_down_is_soft() {
  mk_home; setup "http://127.0.0.1:1"
  out=$(sh "$OB" push global.md); rc=$?
  assert_eq "$rc" 0 rc
  case "$out" in "obsidian mirror skipped: "*) ;; *) echo "$out"; exit 1;; esac
  assert_eq "$(echo "$out" | wc -l | tr -d ' ')" 1 lines
}

test_non_2xx_is_soft() {
  mk_home; stub 401; setup "$URL"
  out=$(sh "$OB" push global.md); rc=$?; kill $SPID
  assert_eq "$rc" 0 rc
  assert_eq "$out" "obsidian mirror skipped: http 401" msg
}

test_key_never_printed() {
  mk_home; stub; setup "$URL"
  out=$(sh "$OB" push global.md 2>&1; sh "$OB" push nope.md 2>&1); kill $SPID
  case "$out" in *sekrit*) echo "key leaked"; exit 1;; esac
  mk_home; setup "http://127.0.0.1:1"
  out=$(sh "$OB" push global.md 2>&1)
  case "$out" in *sekrit*) echo "key leaked"; exit 1;; esac
}

test_traversal_and_url_chars() {
  mk_home; stub; setup "$URL"
  echo secret > "$KAITO_HOME/outside.md"; echo "- q" > "$KAITO_HOME/memory/projects/a#b?c.md"
  out=$(sh "$OB" push 'projects/../../outside.md')
  sh "$OB" push 'projects/a#b?c.md'; kill $SPID
  assert_eq "$out" "obsidian mirror skipped: unknown note projects/../../outside.md" refused
  [ "$IS_WIN" = 0 ] || return 0  # Windows file names cannot contain ?
  assert_eq "$(node -pe 'require("fs").readFileSync(process.argv[1],"utf8").trim().split("\n").map(l=>JSON.parse(l).path).join(" ")' "$REC")" \
    "/vault/madebykaito/helpmekaito/projects/a%23b%3Fc.md" encoded
}

test_key_not_traced() {
  mk_home; stub; setup "$URL"
  out=$(sh -x "$OB" push global.md 2>&1); kill $SPID
  case "$out" in *sekrit*) echo "key leaked under -x"; exit 1;; esac
}

test_mirror_reads_custom_memory_path() {
  mk_home; stub; setup "$URL"
  mkdir -p "$HOME/elsewhere"; echo "- moved" > "$HOME/elsewhere/global.md"
  node "$JS" set "$KAITO_HOME/config.json" memory.path "\"$HOME/elsewhere\""
  sh "$OB" push global.md; kill $SPID
  assert_eq "$(node -pe 'JSON.parse(require("fs").readFileSync(0)).body' < "$REC")" "- moved" body
}

test_mirror_skipped_inside_vault_root() {
  mk_home; stub; setup "$URL"
  mkdir -p "$HOME/vault/kaito"; echo "- in vault" > "$HOME/vault/kaito/global.md"
  node "$JS" set "$KAITO_HOME/config.json" memory.path '"~/vault/kaito"'
  node "$JS" set "$KAITO_HOME/config.json" obsidian.vault_root '"~/vault"'
  out=$(sh "$OB" push global.md); rc=$?
  assert_eq "$rc" 0 rc
  assert_eq "$out" "obsidian mirror skipped: memory is inside the vault" msg
  assert_eq "$(wc -l < "$REC" | tr -d ' ')" 0 requests
  # a memory folder outside the vault still mirrors
  node "$JS" set "$KAITO_HOME/config.json" obsidian.vault_root "\"$HOME/other-vault\""
  sh "$OB" push global.md; kill $SPID
  assert_eq "$(wc -l < "$REC" | tr -d ' ')" 1 requests
}

test_vault_root_skip_is_silent_in_mem() {
  mk_home; stub; setup "$URL"
  mkdir -p "$HOME/vault/kaito" "$HOME/app"
  node "$JS" set "$KAITO_HOME/config.json" memory.path "\"$HOME/vault/kaito\""
  node "$JS" set "$KAITO_HOME/config.json" obsidian.vault_root "\"$HOME/vault\""
  err=$(cd "$HOME/app" && sh "$REPO/helpmekaito/scripts/kaito-mem.sh" note global "x" 2>&1 >/dev/null); kill $SPID
  assert_eq "$err" "" stderr
  assert_eq "$(wc -l < "$REC" | tr -d ' ')" 0 requests
}

test_managers_and_tasks_notes() {
  mk_home; stub; setup "$URL"
  mkdir -p "$KAITO_HOME/memory/managers" "$KAITO_HOME/memory/tasks/app/sub"
  echo "- m" > "$KAITO_HOME/memory/managers/trello.md"
  echo "- t" > "$KAITO_HOME/memory/tasks/app/index.md"
  echo "- x" > "$KAITO_HOME/memory/tasks/app/t-1-a.md"
  echo "- d" > "$KAITO_HOME/memory/tasks/app/sub/index.md"
  sh "$OB" push managers/trello.md; sh "$OB" push tasks/app/index.md
  o1=$(sh "$OB" push tasks/app/t-1-a.md); o2=$(sh "$OB" push tasks/app/sub/index.md)
  o3=$(sh "$OB" push managers/../global.md); o4=$(sh "$OB" push tasks/../../outside/index.md); kill $SPID
  paths=$(node -pe 'require("fs").readFileSync(process.argv[1],"utf8").trim().split("\n").map(l=>JSON.parse(l).path).join(" ")' "$REC")
  assert_eq "$paths" "/vault/madebykaito/helpmekaito/managers/trello.md /vault/madebykaito/helpmekaito/tasks/app/index.md" paths
  for o in "$o1" "$o2" "$o3" "$o4"; do
    case "$o" in "obsidian mirror skipped: unknown note "*) ;; *) echo "$o"; exit 1;; esac
  done
}
