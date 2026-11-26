#!/bin/sh
. "$(dirname "$0")/lib.sh"
M="$REPO/helpmekaito/scripts/kaito-models.mjs"
O="$REPO/helpmekaito/scripts/kaito-ollama.mjs"
U="$REPO/helpmekaito/scripts/kaito-usage.mjs"

# stub: a fake Ollama (extra env goes before the call), OLLAMA_HOST pointed at it; stopped when the test exits.
stub() {
  rm -f "$HOME/port"
  SPID=$(sh -c 'node "$@" >/dev/null 2>&1 & echo $!' _ "$TESTS_DIR/stubs/ollama-api.mjs" "$HOME/port")
  trap 'kill $SPID 2>/dev/null' EXIT
  i=0; while [ ! -s "$HOME/port" ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done
  OLLAMA_HOST="127.0.0.1:$(cat "$HOME/port")"; export OLLAMA_HOST  # bare host:port, the form Ollama itself accepts
}
stats() { node -e 'fetch(process.argv[1]+"/_stats").then(r=>r.json()).then(j=>console.log(j.max+" "+j.calls))' "http://$OLLAMA_HOST"; }

test_resolve_maps_pulled_models_to_tiers() {
  mk_home; stub
  assert_eq "$(node "$M" resolve ollama light)" "ollama llama3.2:1b" "light is the biggest model up to 4B"
  assert_eq "$(node "$M" resolve ollama standard)" "ollama gemma3:12b" "standard is over 4B up to 14B"
  assert_eq "$(node "$M" resolve ollama mid)" "ollama gemma3:12b" "mid is standard"
  assert_eq "$(node "$M" resolve ollama hard)" "ollama llama3.3:70b" "hard is over 14B, and the cloud model is not local"
  assert_eq "$(node "$M" resolve ollama heavy)" "ollama llama3.3:70b" "heavy is hard"
  out=$(node "$M" resolve ollama frontier); case "$out" in host:*) ;; *) echo "  frontier: $out"; exit 1;; esac
}

test_resolve_reports_none_without_a_server_or_a_model() {
  mk_home
  OLLAMA_HOST=http://127.0.0.1:1; export OLLAMA_HOST
  out=$(node "$M" resolve ollama light); case "$out" in "host: Ollama is not running at http://127.0.0.1:1;"*) ;; *) echo "  down: $out"; exit 1;; esac
  STUB_EMPTY=1; export STUB_EMPTY; stub; unset STUB_EMPTY
  out=$(node "$M" resolve ollama light); assert_eq "$out" "host: no Ollama model is pulled; use the host's model" empty
}

test_resolve_with_a_bad_host_prints_the_none_line() {
  mk_home; OLLAMA_HOST=localhost:bad; export OLLAMA_HOST
  out=$(node "$M" resolve ollama light) || exit 1
  case "$out" in "host: OLLAMA_HOST"*"not a valid address;"*) ;; *) echo "  $out"; exit 1;; esac
}

test_resolve_skips_a_failed_model() {
  mk_home; stub
  node "$M" fail ollama llama3.2:1b >/dev/null
  out=$(node "$M" resolve ollama light); assert_eq "$out" "ollama smollm2:360m" "next model of the tier"
}

test_models_available_lists_ollama_without_the_cli() {
  mk_home; stub
  out=$(sh "$REPO/helpmekaito/scripts/models-available.sh")
  printf '%s\n' "$out" | grep -qx "MODELS ollama" || { echo "$out"; exit 1; }
  printf '%s\n' "$out" | grep -qx "  llama3.2:1b  1.2B" || { echo "$out"; exit 1; }
  printf '%s\n' "$out" | grep -qx "  ollama server: yes" || { echo "$out"; exit 1; }
  case "$out" in *embed*|*cloud*) echo "  embedding or cloud model listed"; exit 1;; esac
}

test_consent_is_ok_for_local_ollama() {
  mk_home
  assert_eq "$(node "$U" consent check ollama llama3.2:1b)" ok local
  assert_eq "$(node "$U" consent check ollama gpt-oss:120b-cloud)" ask cloud
}

test_run_returns_the_text() {
  mk_home; stub
  out=$(printf 'say hi\n' | node "$O" run llama3.2:1b) || exit 1
  assert_eq "$out" "llama3.2:1b|say hi" run
  out=$(printf 'good morning' | node "$O" run qwen3:8b --translate-to bn) || exit 1
  case "$out" in *"into Bengali"*"good morning"*) ;; *) echo "  translate: $out"; exit 1;; esac
  rc=0; printf 'x' | node "$O" run nope:1b >/dev/null 2>"$HOME/err" || rc=$?
  assert_eq "$rc" 1 "unknown model"; grep -q "not found" "$HOME/err" || { cat "$HOME/err"; exit 1; }
  rc=0; printf 'x' | node "$O" run llama3.2:1b --translate-to >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" 2 "translate-to needs a language"
  rc=0; : | node "$O" run llama3.2:1b >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" 2 "empty prompt"
}

test_run_without_a_server_says_how_to_fix_it() {
  mk_home; OLLAMA_HOST=http://127.0.0.1:1; export OLLAMA_HOST
  rc=0; out=$(printf 'x' | node "$O" run llama3.2:1b 2>&1) || rc=$?
  assert_eq "$rc" 1 "no server"
  case "$out" in *"cannot reach Ollama at http://127.0.0.1:1"*"OLLAMA_HOST"*) ;; *) echo "  $out"; exit 1;; esac
}

test_bulk_keeps_order_and_limits_concurrency() {
  mk_home; stub
  # The first prompt is slow, so with two workers the later ones finish first: the output must still be in input order.
  printf '%s\n' '{"id":"a","prompt":"slow one"}' '"two"' '{"id":"c","prompt":"three"}' '"four"' '"five"' > "$HOME/in.jsonl"
  node "$O" bulk llama3.2:1b "$HOME/in.jsonl" --concurrency 2 --out "$HOME/out.jsonl" || exit 1
  got=$(node -e 'for (const l of require("fs").readFileSync(process.argv[1],"utf8").split("\n").filter(Boolean)) { const j=JSON.parse(l); console.log(j.i+":"+(j.id||"-")+":"+j.text); }' "$HOME/out.jsonl")
  want="0:a:llama3.2:1b|slow one
1:-:llama3.2:1b|two
2:c:llama3.2:1b|three
3:-:llama3.2:1b|four
4:-:llama3.2:1b|five"
  assert_eq "$got" "$want" "order"
  assert_eq "$(stats)" "2 5" "at most 2 in flight, 5 calls"
  # One at a time.
  node "$O" bulk llama3.2:1b "$HOME/in.jsonl" --concurrency 1 > "$HOME/out1.jsonl" || exit 1
  cmp -s "$HOME/out.jsonl" "$HOME/out1.jsonl" || { echo "  serial run differs"; exit 1; }
}

test_bulk_serial_never_overlaps() {
  mk_home; stub
  printf '%s\n' '"a"' '"b"' '"c"' > "$HOME/in.jsonl"
  node "$O" bulk llama3.2:1b "$HOME/in.jsonl" --concurrency 1 >/dev/null || exit 1
  assert_eq "$(stats)" "1 3" "serial"
}

test_bulk_translates_and_reports_bad_lines() {
  mk_home; stub
  printf '%s\n' '"hello"' '' 'not json' '{"nope":1}' > "$HOME/in.jsonl"
  rc=0; node "$O" bulk qwen3:8b "$HOME/in.jsonl" --translate-to hi > "$HOME/out.jsonl" 2>"$HOME/err" || rc=$?
  assert_eq "$rc" 1 "a failed line exits 1"
  grep -q "2 of 3 prompts failed" "$HOME/err" || { cat "$HOME/err"; exit 1; }
  node -e 'const L=require("fs").readFileSync(process.argv[1],"utf8").split("\n").filter(Boolean).map(JSON.parse);
    if (L.length!==3||!/into Hindi/.test(L[0].text)||!/not JSON/.test(L[1].error)||!/no prompt/.test(L[2].error)||L[1].i!==2||L[2].i!==3) { console.log(JSON.stringify(L)); process.exit(1); }' "$HOME/out.jsonl"
}

test_host_forms() {
  mk_home
  out=$(node --input-type=module -e 'const { ollamaBase } = await import((await import("node:url")).pathToFileURL(process.argv[2]).href);
    console.log([undefined, "", "localhost", "0.0.0.0:11500", "http://10.0.0.5:9", "https://ollama.example", "http://h:1/proxy/", "http://h:80"].map((h) => ollamaBase(h)).join(" "))' import "$O")
  assert_eq "$out" "http://127.0.0.1:11434 http://127.0.0.1:11434 http://localhost:11434 http://127.0.0.1:11500 http://10.0.0.5:9 https://ollama.example http://h:1/proxy http://h" hosts
}
