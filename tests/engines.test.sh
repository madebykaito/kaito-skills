#!/bin/sh
. "$(dirname "$0")/lib.sh"
E="$REPO/business/scripts/kaito-engines.mjs"
REG="$REPO/business/engines/registry.json"

# A home with fake engines only where a test puts them. Every engine path is pinned by an
# environment variable, so the real machine's installs never change a result.
eng_home() {
  mk_home
  unset SVARA_PYTHON PARLER_PYTHON SARVAM_KEY_FILE WHISPER_CPP_BIN OLLAMA_BIN COMFY_URL WAN_MODEL MINIMAX_H3_SCRIPT
  FAKE="$HOME/fake"; mkdir -p "$FAKE"
  HF_HUB_CACHE="$HOME/hf"; export HF_HUB_CACHE
  KAITO_TEST_MEM_GB=64; KAITO_TEST_FREE_GB=60; export KAITO_TEST_MEM_GB KAITO_TEST_FREE_GB
  # Everything the tests do not provide points at a path that does not exist.
  SVARA_PYTHON=/nonexistent/py; PARLER_PYTHON=/nonexistent/py; OLLAMA_BIN=/nonexistent/ollama
  WHISPER_CPP_BIN=/nonexistent/whisper; WAN_MODEL=/nonexistent/wan; MINIMAX_H3_SCRIPT=/nonexistent/h3
  MFLUX_Z_IMAGE_BIN=/nonexistent/z; MFLUX_FLUX2_BIN=/nonexistent/f2; COMFY_URL=http://127.0.0.1:1
  export SVARA_PYTHON PARLER_PYTHON OLLAMA_BIN WHISPER_CPP_BIN WAN_MODEL MINIMAX_H3_SCRIPT MFLUX_Z_IMAGE_BIN MFLUX_FLUX2_BIN COMFY_URL
}
fake_bin() { printf '#!/bin/sh\necho "%s 1.2.3"\n' "$(basename "$1")" > "$1"; chmod +x "$1"; }
fake_model() { mkdir -p "$HF_HUB_CACHE/models--$1/snapshots/abc123"; : > "$HF_HUB_CACHE/models--$1/snapshots/abc123/config.json"; }
jget() { node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(String(eval("j."+process.argv[1])))' "$1"; }

test_doctor_reports_present_and_missing() {
  eng_home
  fake_bin "$FAKE/ollama"; OLLAMA_BIN="$FAKE/ollama"; export OLLAMA_BIN
  mkdir "$FAKE/path"; fake_bin "$FAKE/path/whisper-cli"; unset WHISPER_CPP_BIN
  out=$(PATH="$FAKE/path:$PATH" node "$E" doctor) || exit 1
  echo "$out" | grep -E '^present +ollama ' | grep -q '1.2.3' || { echo "$out"; echo "  ollama should be present with version"; exit 1; }
  echo "$out" | grep -E '^present +whisper-cpp ' >/dev/null || { echo "$out"; echo "  whisper-cli on PATH should be found"; exit 1; }
  echo "$out" | grep -E '^missing +svara ' >/dev/null || { echo "$out"; echo "  svara should be missing"; exit 1; }
  echo "$out" | grep -q 'each capability will use' || { echo "  no summary"; exit 1; }
  echo "$out" | grep -E '^ +llm-bulk +ollama' >/dev/null || { echo "$out"; echo "  llm-bulk should use ollama"; exit 1; }
}

test_doctor_json_parses() {
  eng_home
  node "$E" doctor --json > "$HOME/d.json" || exit 1
  assert_eq "$(jget 'machine.total_ram_gb' < "$HOME/d.json")" 64 total
  assert_eq "$(jget 'providers.find(p=>p.id==="svara").present' < "$HOME/d.json")" false svara
  assert_eq "$(jget 'providers.find(p=>p.id==="svara").license' < "$HOME/d.json")" Apache-2.0 license
  assert_eq "$(jget 'summary.tts.status' < "$HOME/d.json")" none tts
  node "$E" doctor --json --capability tts > "$HOME/t.json" || exit 1
  assert_eq "$(jget 'providers.map(p=>p.id).join()' < "$HOME/t.json")" svara,indic-parler,sarvam,edge-tts ids
  node "$E" doctor --capability nope 2>/dev/null; assert_eq "$?" 2 badcap
}

test_registry_is_complete() {
  node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const need = "tts captions transcribe image likeness video upscale music shortform llm-bulk publish-instagram publish-social email analytics crm".split(" ");
    const must = "svara indic-parler sarvam edge-tts chromium whisper-cpp mflux-z-image-turbo flux2-klein-4b dlib comfyui minimax-h3 ltx seedvr2 acestep moneyprinterturbo ollama host-llm instagram-graph postiz smtp ses listmonk umami twenty".split(" ");
    const bad = [];
    for (const c of need) if (!(r.capabilities[c] || []).length) bad.push("capability " + c);
    for (const id of must) if (!r.providers[id]) bad.push("provider " + id);
    const used = new Set(Object.values(r.capabilities).flat());
    for (const [c, ids] of Object.entries(r.capabilities)) for (const id of ids) if (!r.providers[id]) bad.push(c + " names unknown " + id);
    for (const [id, p] of Object.entries(r.providers)) {
      if (!used.has(id)) bad.push(id + " unused");
      if (!["local", "cloud"].includes(p.kind)) bad.push(id + " kind");
      if (typeof p.license?.id !== "string" || typeof p.license.commercial !== "boolean") bad.push(id + " license");
      if (!/^https?:\/\//.test(p.source || "")) bad.push(id + " source");
      if (typeof p.min_ram_gb !== "number" || typeof p.disk_gb !== "number") bad.push(id + " ram/disk");
      if (!p.checks && !p.key) bad.push(id + " has no check");
      if (p.kind === "cloud" && !p.key && !p.checks) bad.push(id + " cloud check");
      if (p.key && !/<owner>/.test(p.key.pattern)) bad.push(id + " key pattern");
      if (!p.license.commercial && p.enabled !== false) bad.push(id + " non-commercial but enabled");
      if (p.env === undefined && !(p.checks || []).some((c) => c.type === "always")) bad.push(id + " env");
    }
    if (r.providers["minimax-h3"].license.id !== "MiniMax-H3-Community") bad.push("h3 license id");
    if (bad.length) { console.log(bad.join("\n")); process.exit(1); }
  ' "$REG" || exit 1
}

test_pick_order_and_override() {
  eng_home
  fake_bin "$FAKE/py"; SVARA_PYTHON="$FAKE/py"; PARLER_PYTHON="$FAKE/py"; export SVARA_PYTHON PARLER_PYTHON
  fake_model kenpath--svara-tts-v1; fake_model ai4bharat--indic-parler-tts
  out=$(node "$E" pick tts) || exit 1
  assert_eq "$(echo "$out" | sed -n 1p)" provider=svara first
  assert_eq "$(echo "$out" | sed -n 2p)" "path=$FAKE/py" path
  # engines.json reorders: listed providers first, the rest keep their order.
  mkdir -p "$KAITO_HOME"
  echo '{"capabilities":{"tts":["indic-parler"]}}' > "$KAITO_HOME/engines.json"
  assert_eq "$(node "$E" pick tts | sed -n 1p)" provider=indic-parler reordered
  # disable moves on to the next one
  echo '{"providers":{"indic-parler":{"enabled":false}},"capabilities":{"tts":["indic-parler"]}}' > "$KAITO_HOME/engines.json"
  assert_eq "$(node "$E" pick tts | sed -n 1p)" provider=svara disabled
  # a path in engines.json replaces the default; an env var beats engines.json
  fake_bin "$FAKE/mine"; fake_bin "$FAKE/envwins"
  echo "{\"providers\":{\"whisper-cpp\":{\"path\":\"$FAKE/mine\"}}}" > "$KAITO_HOME/engines.json"
  unset WHISPER_CPP_BIN
  assert_eq "$(node "$E" pick transcribe | sed -n 2p)" "path=$FAKE/mine" jsonpath
  WHISPER_CPP_BIN="$FAKE/envwins" node "$E" pick transcribe | grep -q "path=$FAKE/envwins" || { echo "  env should win"; exit 1; }
  # a missing override is missing, not a silent fall back to PATH
  WHISPER_CPP_BIN="$FAKE/gone" node "$E" pick transcribe 2>/dev/null; assert_eq "$?" 4 stale
  # a broken engines.json is an error, not silently ignored
  echo '{bad' > "$KAITO_HOME/engines.json"
  node "$E" pick tts 2>/dev/null; assert_eq "$?" 1 badjson
}

test_pick_none_exits_4_and_usage_2() {
  eng_home
  node "$E" pick tts 2>"$HOME/err"; assert_eq "$?" 4 none
  grep -q 'svara: missing' "$HOME/err" || { cat "$HOME/err"; echo "  reasons missing"; exit 1; }
  node "$E" pick nope 2>/dev/null; assert_eq "$?" 2 unknowncap
  node "$E" pick tts --owner '../x' 2>/dev/null; assert_eq "$?" 2 badowner
  node "$E" consent svara --owner lumen-tea --grant 2>/dev/null; assert_eq "$?" 2 localconsent
}

test_cloud_needs_consent() {
  eng_home
  mkdir -p "$HOME/.config/sarvam"; : > "$HOME/.config/sarvam/lumen-tea.env"
  node "$E" pick tts --owner lumen-tea 2>"$HOME/err"; assert_eq "$?" 4 nocloudflag
  grep -q -- '--allow-cloud' "$HOME/err" || { echo "  should hint --allow-cloud"; exit 1; }
  node "$E" pick tts --allow-cloud --owner lumen-tea 2>"$HOME/err"; assert_eq "$?" 3 noconsent
  grep -q 'consent sarvam --owner lumen-tea --grant' "$HOME/err" || { cat "$HOME/err"; echo "  should name the consent command"; exit 1; }
  node "$E" pick tts --allow-cloud 2>/dev/null; assert_eq "$?" 3 noowner
  node "$E" consent sarvam --owner lumen-tea --grant >/dev/null || exit 1
  assert_file "$KAITO_HOME/owners/lumen-tea/consent.json"
  out=$(node "$E" pick tts --allow-cloud --owner lumen-tea) || exit 1
  assert_eq "$(echo "$out" | sed -n 1p)" provider=sarvam granted
  assert_eq "$(echo "$out" | sed -n 2p)" "path=$HOME/.config/sarvam/lumen-tea.env" keypath
  # consent is per owner and per provider
  : > "$HOME/.config/sarvam/ira-das.env"
  node "$E" pick tts --allow-cloud --owner ira-das 2>/dev/null; assert_eq "$?" 3 otherowner
  # the key file's contents are never printed
  echo 'SARVAM_API_KEY=sekrit-value' > "$HOME/.config/sarvam/lumen-tea.env"
  node "$E" doctor --owner lumen-tea > "$HOME/doc.txt"; node "$E" doctor --json >> "$HOME/doc.txt"
  ! grep -q sekrit "$HOME/doc.txt" || { echo "  key value leaked"; exit 1; }
  node "$E" consent sarvam --owner lumen-tea --revoke >/dev/null || exit 1
  node "$E" pick tts --allow-cloud --owner lumen-tea 2>/dev/null; assert_eq "$?" 3 revoked
  assert_eq "$(node "$E" consent sarvam --owner lumen-tea --status)" "sarvam for lumen-tea: not granted" status
}

test_cloud_missing_key_is_unusable() {
  eng_home
  node "$E" consent sarvam --owner lumen-tea --grant >/dev/null || exit 1
  node "$E" pick tts --allow-cloud --owner lumen-tea 2>/dev/null; assert_eq "$?" 4 nokey
}

test_ram_refusal() {
  eng_home
  fake_bin "$FAKE/py"; SVARA_PYTHON="$FAKE/py"; export SVARA_PYTHON; fake_model kenpath--svara-tts-v1
  node "$E" pick tts >/dev/null || exit 1
  KAITO_TEST_FREE_GB=2 node "$E" pick tts 2>"$HOME/err"; assert_eq "$?" 3 lowfree
  grep -q 'needs 8 GB RAM' "$HOME/err" && grep -q 'swap' "$HOME/err" || { cat "$HOME/err"; echo "  reason missing"; exit 1; }
  KAITO_TEST_FREE_GB=2 node "$E" pick tts --force | grep -q provider=svara || { echo "  --force should pick"; exit 1; }
  KAITO_TEST_MEM_GB=4 KAITO_TEST_FREE_GB=4 node "$E" pick tts 2>"$HOME/err"; assert_eq "$?" 3 smalltotal
  grep -q 'this machine has 4 GB' "$HOME/err" || { cat "$HOME/err"; echo "  total reason"; exit 1; }
  # a light provider is never refused for RAM
  fake_bin "$FAKE/w"; WHISPER_CPP_BIN="$FAKE/w" KAITO_TEST_FREE_GB=0.1 node "$E" pick transcribe >/dev/null || { echo "  light provider refused"; exit 1; }
}

test_noncommercial_off_by_default() {
  eng_home
  : > "$FAKE/h3.py"; MINIMAX_H3_SCRIPT="$FAKE/h3.py"; export MINIMAX_H3_SCRIPT
  node "$E" pick video 2>"$HOME/err"; assert_eq "$?" 4 off
  grep -q 'minimax-h3: disabled' "$HOME/err" || { cat "$HOME/err"; echo "  should say disabled"; exit 1; }
  node "$E" doctor --json > "$HOME/d.json"
  assert_eq "$(jget 'providers.find(p=>p.id==="minimax-h3").enabled' < "$HOME/d.json")" false h3off
  assert_eq "$(jget 'providers.find(p=>p.id==="minimax-h3").present' < "$HOME/d.json")" true h3present
  assert_eq "$(jget 'providers.find(p=>p.id==="minimax-h3").commercial' < "$HOME/d.json")" false h3commercial
  assert_eq "$(jget 'providers.find(p=>p.id==="edge-tts").enabled' < "$HOME/d.json")" false edgeoff
  node "$E" enable minimax-h3 2>"$HOME/err" >/dev/null || exit 1
  grep -q 'not cleared for commercial use' "$HOME/err" || { echo "  enable should warn"; exit 1; }
  out=$(node "$E" pick video 2>/dev/null) || exit 1
  assert_eq "$(echo "$out" | sed -n 1p)" provider=minimax-h3 optin
  assert_eq "$(echo "$out" | grep commercial)" commercial=no flag
  node "$E" disable minimax-h3 >/dev/null || exit 1
  node "$E" pick video 2>/dev/null; assert_eq "$?" 4 off_again
}

test_http_probe_and_url_override() {
  eng_home
  node -e '
    const s = require("http").createServer((q, r) => { r.end("{}"); });
    s.listen(0, "127.0.0.1", () => require("fs").writeFileSync(process.argv[1], String(s.address().port)));
  ' "$HOME/port" &
  srv=$!
  trap 'kill $srv 2>/dev/null' EXIT
  i=0; while [ ! -s "$HOME/port" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  [ -s "$HOME/port" ] || { echo "  stub did not start"; exit 1; }
  COMFY_URL="http://127.0.0.1:$(cat "$HOME/port")"; export COMFY_URL
  out=$(node "$E" pick image) || exit 1
  assert_eq "$(echo "$out" | sed -n 1p)" provider=comfyui comfy
  assert_eq "$(echo "$out" | sed -n 2p)" "path=$COMFY_URL" url
  COMFY_URL=http://127.0.0.1:1 node "$E" pick image 2>/dev/null; assert_eq "$?" 4 down
}

test_new_provider_in_engines_json() {
  eng_home
  fake_bin "$FAKE/mytts"
  mkdir -p "$KAITO_HOME"
  cat > "$KAITO_HOME/engines.json" <<EOF
{"providers":{"my-tts":{"name":"My TTS","kind":"local","checks":[{"type":"bin","names":[],"paths":["$FAKE/mytts"]}],"license":{"id":"MIT","commercial":true}}},
 "capabilities":{"tts":["my-tts"]}}
EOF
  assert_eq "$(node "$E" pick tts | sed -n 1p)" provider=my-tts custom
  echo '{"capabilities":{"tts":["ghost"]}}' > "$KAITO_HOME/engines.json"
  node "$E" doctor 2>&1 | grep -q 'unknown provider ghost' || { echo "  should warn about ghost"; exit 1; }
}

test_remote_url_credentials_not_printed() {
  eng_home
  COMFY_URL="http://u:tok@127.0.0.2:1/x?token=abc"; export COMFY_URL
  out=$(node "$E" doctor 2>&1; node "$E" doctor --json 2>&1)
  ! echo "$out" | grep -q -e tok -e abc || { echo "  URL credentials leaked"; exit 1; }
}

test_consent_must_be_literal_true_and_ids_fixed() {
  eng_home
  mkdir -p "$HOME/.config/sarvam" "$KAITO_HOME/owners/lumen-tea"; : > "$HOME/.config/sarvam/lumen-tea.env"
  echo '{"version":1,"cloud":{"sarvam":{"granted":"false"}}}' > "$KAITO_HOME/owners/lumen-tea/consent.json"
  node "$E" pick tts --allow-cloud --owner lumen-tea 2>/dev/null; assert_eq "$?" 3 stringfalse
  echo '{"providers":{"sarvam":{"kind":"local","id":"svara"}}}' > "$KAITO_HOME/engines.json"
  node "$E" pick tts --allow-cloud --owner lumen-tea 2>/dev/null; assert_eq "$?" 3 kindlocked
  node "$E" pick constructor 2>/dev/null; assert_eq "$?" 2 inherited
  echo '{"providers":{"x-y":{"kind":"local","checks":[],"license":{"id":"MIT","commercial":false}}}}' > "$KAITO_HOME/engines.json"
  node "$E" doctor 2>&1 | grep -q 'x-y needs kind' || { echo "  empty checks should be rejected"; exit 1; }
}

test_custom_noncommercial_provider_starts_off() {
  eng_home; mkdir -p "$KAITO_HOME"
  fake_bin "$FAKE/mytts"
  echo "{\"providers\":{\"my-tts\":{\"kind\":\"local\",\"checks\":[{\"type\":\"bin\",\"names\":[],\"paths\":[\"/stale\"]}],\"path\":\"$FAKE/mytts\",\"license\":{\"id\":\"X\",\"commercial\":false}}},\"capabilities\":{\"tts\":[\"my-tts\"]}}" > "$KAITO_HOME/engines.json"
  node "$E" pick tts 2>/dev/null; assert_eq "$?" 4 off
  node "$E" enable my-tts >/dev/null 2>&1 || exit 1
  assert_eq "$(node "$E" pick tts 2>/dev/null | sed -n 2p)" "path=$FAKE/mytts" newpath
}

test_bad_ram_override_is_ignored() {
  eng_home
  fake_bin "$FAKE/py"; SVARA_PYTHON="$FAKE/py"; export SVARA_PYTHON; fake_model kenpath--svara-tts-v1
  KAITO_TEST_FREE_GB=abc KAITO_TEST_MEM_GB=64 node "$E" doctor >/dev/null || exit 1
}
