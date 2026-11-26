#!/bin/sh
. "$(dirname "$0")/lib.sh"
VO="$REPO/voiceover/scripts/voiceover.py"

# need_tools: end the test with a skip line when ffmpeg or python3 is missing (CI has no ffmpeg).
need_tools() {
  command -v python3 >/dev/null 2>&1 || { echo "skip: python3 not installed"; return 1; }
  command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1 || { echo "skip: ffmpeg not installed"; return 1; }
}

# fake_svara <dir>: a stand-in for `python -m mlx_audio.tts.generate`. Line N lasts 1+0.5N seconds.
fake_svara() {
  mkdir -p "$1"
  cat > "$1/fake-svara" <<'EOF'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
while [ $# -gt 0 ]; do case "$1" in --output_path) o="$2";; --file_prefix) p="$2";; esac; shift; done
n=${p#l}
d=$(awk "BEGIN{print 1+0.5*$n}")
ffmpeg -v error -y -f lavfi -i "sine=frequency=440:duration=$d" -ar 24000 "$o/${p}_000.wav"
EOF
  chmod +x "$1/fake-svara"
}

# log_ffmpeg <dir>: a wrapper first in PATH that records every ffmpeg call, then runs the real one.
log_ffmpeg() {
  real=$(command -v ffmpeg); mkdir -p "$1"
  printf '#!/bin/sh\necho "$*" >> "%s/ffmpeg.log"\nexec "%s" "$@"\n' "$1" "$real" > "$1/ffmpeg"
  chmod +x "$1/ffmpeg"
}

lines_file() {
  cat > "$1" <<'EOF'
{"language":"en-IN","lines":[
 {"text":"One.","tone":"warm","pause_after":0.4},
 {"text":"Two, with a <happy> tag left out by the agent.","tone":"calm","pause_after":0.2},
 {"text":"Three.","pause_after":0.5}]}
EOF
}

test_voiceover_svara_parts() {
  mk_home; need_tools || return 0
  fake_svara "$HOME/bin"; log_ffmpeg "$HOME/bin"; PATH="$HOME/bin:$PATH"
  FAKE_LOG="$HOME/svara.log"; export FAKE_LOG SVARA_PYTHON="$HOME/bin/fake-svara"
  lines_file "$HOME/l.json"
  python3 "$VO" --lines "$HOME/l.json" --out-dir "$HOME/out" > "$HOME/o.txt" 2>&1; rc=$?
  [ $rc = 0 ] || { cat "$HOME/o.txt"; exit 1; }
  assert_file "$HOME/out/voice.wav"; assert_file "$HOME/out/parts.json"; assert_file "$HOME/out/lines/line02.wav"
  assert_eq "$(ffprobe -v error -show_entries stream=sample_rate -of csv=p=0 "$HOME/out/voice.wav")" 48000 rate
  assert_eq "$(wc -l < "$HOME/svara.log" | tr -d ' ')" 3 "one request per line"
  # the model and voice reach the engine, and emotion tags are stripped before the engine sees the text
  grep -q 'kenpath/svara-tts-v1' "$HOME/svara.log" || { echo "  model missing"; exit 1; }
  ! grep -q '<happy>' "$HOME/svara.log" || { echo "  emotion tag reached svara"; exit 1; }
  python3 - "$HOME/out" <<'EOF' || exit 1
import json, subprocess, sys
out = sys.argv[1]
p = json.load(open(out + "/parts.json"))
def dur(f):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", f]).decode())
L = p["lines"]
assert len(L) == 3 and p["sample_rate"] == 48000 and p["version"] == 1
assert L[0]["clip_start"] == 0
for i, l in enumerate(L):
    assert abs(dur(out + "/" + l["file"]) - l["duration"]) < 0.01, ("file duration", i)
    assert abs(l["start"] - l["clip_start"] - 0.12) < 0.002, ("speech starts after the breath", i)
    assert abs(l["clip_end"] - l["clip_start"] - l["duration"]) < 0.002, ("clip", i)
    assert abs((l["clip_end"] - l["end"]) - l["pause_after"]) < 0.01, ("pause", i)
    assert l["end"] > l["start"], ("end", i)
    if i:
        assert abs(L[i - 1]["clip_end"] - l["clip_start"]) < 0.002, ("gap", i)
assert abs(sum(l["duration"] for l in L) - dur(out + "/voice.wav")) < 0.05, "parts add up to voice.wav"
assert abs(p["duration"] - dur(out + "/voice.wav")) < 0.01
EOF
}

test_voiceover_loudnorm_called() {
  mk_home; need_tools || return 0
  fake_svara "$HOME/bin"; log_ffmpeg "$HOME/bin"; PATH="$HOME/bin:$PATH"
  FAKE_LOG="$HOME/svara.log"; export FAKE_LOG SVARA_PYTHON="$HOME/bin/fake-svara"
  lines_file "$HOME/l.json"
  python3 "$VO" --lines "$HOME/l.json" --out-dir "$HOME/out" >/dev/null 2>&1 || exit 1
  grep -q 'loudnorm=I=-16' "$HOME/bin/ffmpeg.log" || { echo "  loudnorm not called"; exit 1; }
  grep -q 'silenceremove' "$HOME/bin/ffmpeg.log" || { echo "  trim not called"; exit 1; }
  grep -q 'linear=true' "$HOME/bin/ffmpeg.log" || { echo "  second loudnorm pass missing"; exit 1; }
  lufs=$(ffmpeg -hide_banner -nostats -i "$HOME/out/voice.wav" -af ebur128 -f null - 2>&1 | awk '/ I: / {v=$2} END {print v}')
  awk -v v="$lufs" 'BEGIN{exit !(v > -17.5 && v < -14.5)}' || { echo "  loudness $lufs not near -16"; exit 1; }
}

test_voiceover_engine_missing() {
  mk_home; need_tools || return 0
  lines_file "$HOME/l.json"
  SVARA_PYTHON="$HOME/nope/python" python3 "$VO" --lines "$HOME/l.json" --out-dir "$HOME/out" > "$HOME/o.txt" 2>&1; rc=$?
  assert_eq "$rc" 4 rc
  grep -q 'SVARA_PYTHON' "$HOME/o.txt" || { echo "  no hint"; exit 1; }
}

test_voiceover_bad_lines() {
  mk_home; need_tools || return 0
  echo '{"lines":[]}' > "$HOME/l.json"
  python3 "$VO" --lines "$HOME/l.json" --out-dir "$HOME/out" >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 2 rc
}

test_voiceover_cloud_refused_without_consent() {
  mk_home; need_tools || return 0
  mkdir -p "$HOME/.config/sarvam"; echo 'SARVAM_API_KEY=sk-test-secret-123' > "$HOME/.config/sarvam/lumen-tea.env"
  lines_file "$HOME/l.json"
  KAITO_HOME="$HOME/.kaito" python3 "$VO" --engine sarvam --owner lumen-tea --lines "$HOME/l.json" --out-dir "$HOME/out" > "$HOME/o.txt" 2>&1; rc=$?
  assert_eq "$rc" 3 rc
  grep -q 'cloud' "$HOME/o.txt" || { echo "  no cloud message"; exit 1; }
  ! grep -q 'sk-test-secret' "$HOME/o.txt" || { echo "  key printed"; exit 1; }
  assert_no "$HOME/out/voice.wav"
}

test_voiceover_cloud_consent_tool() {
  mk_home; need_tools || return 0; command -v node >/dev/null 2>&1 || { echo "skip: node not installed"; return 0; }
  mkdir -p "$HOME/.config/sarvam" "$KAITO_HOME/store/business/scripts"
  echo 'SARVAM_API_KEY=sk-test-secret-123' > "$HOME/.config/sarvam/lumen-tea.env"
  # a consent tool that says no: the call is refused even with --cloud-ok
  echo 'process.exit(3)' > "$KAITO_HOME/store/business/scripts/kaito-engines.mjs"
  lines_file "$HOME/l.json"
  python3 "$VO" --engine sarvam --owner lumen-tea --cloud-ok --lines "$HOME/l.json" --out-dir "$HOME/out" >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 3 "tool says no"
}

grant_sarvam_fixture() {
  mkdir -p "$KAITO_HOME/owners/lumen-tea"
  node "$REPO/business/scripts/kaito-engines.mjs" consent sarvam --owner lumen-tea --grant >/dev/null || exit 1
}

test_voiceover_sarvam_stub() {
  mk_home; need_tools || return 0
  grant_sarvam_fixture
  mkdir -p "$HOME/.config/sarvam" "$HOME/srv"
  echo 'SARVAM_API_KEY=sk-test-secret-123' > "$HOME/.config/sarvam/lumen-tea.env"
  ffmpeg -v error -y -f lavfi -i "sine=frequency=300:duration=1" -ar 44100 "$HOME/srv/a.wav"
  cat > "$HOME/srv/stub.py" <<'EOF'
import base64, http.server, json, sys
audio = base64.b64encode(open(sys.argv[1] + "/a.wav", "rb").read()).decode()
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers["Content-Length"]); body = json.loads(self.rfile.read(n))
        assert self.headers["api-subscription-key"] == "sk-test-secret-123" and body["text"]
        out = json.dumps({"audios": [audio]}).encode()
        self.send_response(200); self.send_header("Content-Length", str(len(out))); self.end_headers(); self.wfile.write(out)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1] + "/port", "w").write(str(s.server_port))
s.serve_forever()
EOF
  python3 "$HOME/srv/stub.py" "$HOME/srv" & pid=$!
  i=0; while [ ! -s "$HOME/srv/port" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  lines_file "$HOME/l.json"
  SARVAM_API="http://127.0.0.1:$(cat "$HOME/srv/port")/tts" python3 "$VO" --engine sarvam --owner lumen-tea --cloud-ok \
    --lines "$HOME/l.json" --out-dir "$HOME/out" > "$HOME/o.txt" 2>&1; rc=$?
  kill $pid 2>/dev/null
  [ $rc = 0 ] || { cat "$HOME/o.txt"; exit 1; }
  assert_eq "$(ffprobe -v error -show_entries stream=sample_rate -of csv=p=0 "$HOME/out/voice.wav")" 48000 rate
  ! grep -q 'sk-test-secret' "$HOME/o.txt" "$HOME/out/parts.json" || { echo "  key leaked"; exit 1; }
}

test_voiceover_consent_status_not_granted() {
  mk_home; need_tools || return 0; command -v node >/dev/null 2>&1 || { echo "skip: node not installed"; return 0; }
  mkdir -p "$HOME/.config/sarvam" "$KAITO_HOME/store/business/scripts"
  echo 'SARVAM_API_KEY=sk-test-secret-123' > "$HOME/.config/sarvam/lumen-tea.env"
  # the real tool exits 0 for "not granted": that is still a refusal
  echo 'console.log("sarvam for lumen-tea: not granted")' > "$KAITO_HOME/store/business/scripts/kaito-engines.mjs"
  lines_file "$HOME/l.json"
  python3 "$VO" --engine sarvam --owner lumen-tea --cloud-ok --lines "$HOME/l.json" --out-dir "$HOME/out" >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 3 "not granted"
  # granted passes consent; with no key file the next stop is exit 4
  echo 'console.log("sarvam for ira-das: granted")' > "$KAITO_HOME/store/business/scripts/kaito-engines.mjs"
  python3 "$VO" --engine sarvam --owner ira-das --lines "$HOME/l.json" --out-dir "$HOME/out" >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 4 "granted, no key"
}

test_voiceover_sarvam_endpoint_pinned() {
  mk_home; command -v python3 >/dev/null 2>&1 || { echo "skip: python3 not installed"; return 0; }
  u=$(SARVAM_API=http://evil.example/steal python3 -c "import sys; sys.path.insert(0, '$REPO/voiceover/scripts'); import voiceover; print(voiceover.sarvam_url())")
  assert_eq "$u" "https://api.sarvam.ai/text-to-speech" pinned
  u=$(SARVAM_API=http://127.0.0.1:9/x python3 -c "import sys; sys.path.insert(0, '$REPO/voiceover/scripts'); import voiceover; print(voiceover.sarvam_url())")
  assert_eq "$u" "http://127.0.0.1:9/x" local
}

test_voiceover_owner_id_checked() {
  mk_home; need_tools || return 0
  lines_file "$HOME/l.json"
  python3 "$VO" --engine sarvam --owner ../../etc/x --cloud-ok --lines "$HOME/l.json" --out-dir "$HOME/out" >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 2 "path as owner"
}

test_voiceover_bad_types() {
  mk_home; need_tools || return 0
  echo '{"lines":[{"text":5}]}' > "$HOME/l.json"
  python3 "$VO" --lines "$HOME/l.json" --out-dir "$HOME/out" >/dev/null 2>&1; assert_eq "$?" 2 "numeric text"
  echo '{"lines":[{"text":"a","pause_after":"x"}]}' > "$HOME/l.json"
  python3 "$VO" --lines "$HOME/l.json" --out-dir "$HOME/out" >/dev/null 2>&1; assert_eq "$?" 2 "bad pause"
  echo '5' > "$HOME/l.json"
  python3 "$VO" --lines "$HOME/l.json" --out-dir "$HOME/out" >/dev/null 2>&1; assert_eq "$?" 2 "scalar"
}

test_voiceover_engine_package_missing() {
  mk_home; need_tools || return 0
  printf '#!/bin/sh\necho "/x/python: No module named mlx_audio" >&2\nexit 1\n' > "$HOME/py"; chmod +x "$HOME/py"
  lines_file "$HOME/l.json"
  SVARA_PYTHON="$HOME/py" python3 "$VO" --lines "$HOME/l.json" --out-dir "$HOME/out" >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 4 "package missing is not found"
}

test_voiceover_caption_text_has_no_tags() {
  mk_home; need_tools || return 0
  fake_svara "$HOME/bin"; PATH="$HOME/bin:$PATH"
  FAKE_LOG="$HOME/svara.log"; export FAKE_LOG SVARA_PYTHON="$HOME/bin/fake-svara"
  lines_file "$HOME/l.json"
  python3 "$VO" --lines "$HOME/l.json" --out-dir "$HOME/out" >/dev/null 2>&1 || exit 1
  ! grep -q '<happy>' "$HOME/out/parts.json" || { echo "  tag in parts.json"; exit 1; }
}

test_voiceover_short_clip_loudnorm_falls_back() {
  mk_home; need_tools || return 0
  ffmpeg -v error -y -f lavfi -i "sine=frequency=440:duration=0.25" "$HOME/s.wav"
  f=$(python3 -c "import sys; sys.path.insert(0, '$REPO/voiceover/scripts'); import voiceover; print(voiceover.loudnorm_filter('$HOME/s.wav', -16))")
  ffmpeg -v error -y -i "$HOME/s.wav" -af "$f" "$HOME/o.wav" || { echo "  filter rejected: $f"; exit 1; }
}

test_voiceover_sarvam_redirect_not_followed() {
  mk_home; need_tools || return 0
  grant_sarvam_fixture
  mkdir -p "$HOME/.config/sarvam" "$HOME/srv"
  echo 'SARVAM_API_KEY=sk-test-secret-123' > "$HOME/.config/sarvam/lumen-tea.env"
  cat > "$HOME/srv/stub.py" <<'PY'
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers["Content-Length"]))
        self.send_response(307); self.send_header("Location", "http://127.0.0.1:1/x"); self.send_header("Content-Length", "0"); self.end_headers()
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1] + "/port", "w").write(str(s.server_port))
s.serve_forever()
PY
  python3 "$HOME/srv/stub.py" "$HOME/srv" & pid=$!
  i=0; while [ ! -s "$HOME/srv/port" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  lines_file "$HOME/l.json"
  SARVAM_API="http://127.0.0.1:$(cat "$HOME/srv/port")/tts" python3 "$VO" --engine sarvam --owner lumen-tea --cloud-ok \
    --lines "$HOME/l.json" --out-dir "$HOME/out" > "$HOME/o.txt" 2>&1; rc=$?
  kill $pid 2>/dev/null
  assert_eq "$rc" 1 "redirect is a failure"
  grep -q 'sarvam request failed' "$HOME/o.txt" || { echo "  expected a refused redirect"; cat "$HOME/o.txt"; exit 1; }
}
