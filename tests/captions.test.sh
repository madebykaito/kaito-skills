#!/bin/sh
. "$(dirname "$0")/lib.sh"
CAP="$REPO/captions/scripts/captions.py"

need_py() { command -v python3 >/dev/null 2>&1 || { echo "skip: python3 not installed"; return 1; }; }
need_ff() { command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1 || { echo "skip: ffmpeg not installed"; return 1; }; }

# fake_chrome <path>: writes a 1x1 PNG where --screenshot=<file> says, and records the page it was given.
fake_chrome() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
#!/usr/bin/env python3
import base64, sys
png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
out = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--screenshot=")][0]
open(out, "wb").write(png)
page = sys.argv[-1]
import os
d = os.environ.get("FAKE_PAGES")
if d and page.startswith("file://"):
    os.makedirs(d, exist_ok=True)
    src = page[7:]
    open(d + "/" + os.path.basename(src) + ".txt", "w").write(open(src, encoding="utf-8").read())
EOF
  chmod +x "$1"
}

parts_file() {
  cat > "$1" <<'EOF'
{"version":1,"duration":6.5,"lines":[
 {"text":"ক্ষ ন্দ্র স্ত্র","start":0.12,"end":2.0},
 {"text":"one two three four","start":2.5,"end":4.5},
 {"text":"last","start":5.0,"end":6.0,"caption":"LAST"}]}
EOF
}

test_captions_render_timing() {
  mk_home; need_py || return 0
  fake_chrome "$HOME/bin/chrome"; CHROME="$HOME/bin/chrome"; FAKE_PAGES="$HOME/pages"; export CHROME FAKE_PAGES
  parts_file "$HOME/p.json"
  python3 "$CAP" render --parts "$HOME/p.json" --out-dir "$HOME/cap" > "$HOME/o.txt" 2>&1 || { cat "$HOME/o.txt"; exit 1; }
  for f in cap00.png cap01.png cap02.png blank.png captions.json concat.txt overlay.filter overlay.args; do assert_file "$HOME/cap/$f"; done
  python3 - "$HOME/cap" "$HOME/pages" <<'EOF' || exit 1
import json, sys
d = sys.argv[1]
pages = sys.argv[2]
c = json.load(open(d + "/captions.json", encoding="utf-8"))["captions"]
assert [(x["start"], x["end"]) for x in c] == [(0.12, 2.0), (2.5, 4.5), (5.0, 6.0)], c
assert c[2]["text"] == "LAST"
assert c[0]["text"] == "ক্ষ ন্দ্র স্ত্র"
# the page Chrome was given carries the text, full width, transparent
html = open(pages + "/cap00.html.txt", encoding="utf-8").read()
assert "ক্ষ ন্দ্র স্ত্র" in html and "background:transparent" in html and "text-wrap" not in html and "<br" not in html
# concat list: blank for the first 0.12 s, then caption, gaps are blank
rows = open(d + "/concat.txt").read().splitlines()
assert rows[-1] == "file blank.png"
assert rows[0] == "ffconcat version 1.0" and rows[1] == "file blank.png" and rows[2] == "duration 0.120"
assert "file cap01.png" in rows and "file cap02.png" in rows
total = sum(float(r.split()[1]) for r in rows if r.startswith("duration"))
assert abs(total - 6.5) < 0.01, total  # the trailing pause is kept
EOF
}

test_captions_max_words_split() {
  mk_home; need_py || return 0
  fake_chrome "$HOME/bin/chrome"; CHROME="$HOME/bin/chrome"; export CHROME
  echo '{"lines":[{"text":"aaaa bbbb cccc dddd","start":0,"end":4}]}' > "$HOME/p.json"
  python3 "$CAP" render --parts "$HOME/p.json" --out-dir "$HOME/cap" --max-words 2 --lead 1 >/dev/null 2>&1 || exit 1
  python3 - "$HOME/cap" <<'EOF' || exit 1
import json, sys
c = json.load(open(sys.argv[1] + "/captions.json"))["captions"]
assert [(x["text"], x["start"], x["end"]) for x in c] == [("aaaa bbbb", 1.0, 3.0), ("cccc dddd", 3.0, 5.0)], c
EOF
}

test_captions_overlay_filter_runs() {
  mk_home; need_py || return 0; need_ff || return 0
  fake_chrome "$HOME/bin/chrome"; CHROME="$HOME/bin/chrome"; export CHROME
  parts_file "$HOME/p.json"
  python3 "$CAP" render --parts "$HOME/p.json" --out-dir "$HOME/cap" --y 10 >/dev/null 2>&1 || exit 1
  grep -q "enable='gte(t,0.120)\\*lt(t,2.000)'" "$HOME/cap/overlay.filter" || { echo "  filter timing"; exit 1; }
  grep -q '\[vout\]' "$HOME/cap/overlay.filter" || { echo "  no vout"; exit 1; }
  set -- $(sed 's/^/ /' "$HOME/cap/overlay.args" | tr '\n' ' ')
  ffmpeg -v error -y -f lavfi -i "color=c=black:s=1080x1920:d=7:r=10" "$@" -filter_complex "$(cat "$HOME/cap/overlay.filter")" \
    -map '[vout]' -t 7 "$HOME/out.mp4" || { echo "  ffmpeg overlay failed"; exit 1; }
  assert_eq "$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$HOME/out.mp4")" "1080,1920" size
  # the ffconcat list is readable by ffmpeg too
  ffmpeg -v error -y -f concat -safe 0 -i "$HOME/cap/concat.txt" -t 1 "$HOME/track.mp4" || { echo "  concat unreadable"; exit 1; }
}

test_captions_chrome_missing() {
  mk_home; need_py || return 0
  parts_file "$HOME/p.json"
  CHROME="$HOME/nope/chrome" python3 "$CAP" render --parts "$HOME/p.json" --out-dir "$HOME/cap" > "$HOME/o.txt" 2>&1; rc=$?
  assert_eq "$rc" 4 rc
  grep -q 'CHROME' "$HOME/o.txt" || { echo "  no hint"; cat "$HOME/o.txt"; exit 1; }
  ! grep -q 'Traceback' "$HOME/o.txt" || { echo "  traceback"; exit 1; }
}

test_captions_bad_parts() {
  mk_home; need_py || return 0
  fake_chrome "$HOME/bin/chrome"; CHROME="$HOME/bin/chrome"; export CHROME
  echo '{"lines":[{"text":"x"}]}' > "$HOME/p.json"
  python3 "$CAP" render --parts "$HOME/p.json" --out-dir "$HOME/cap" >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 2 rc
}

test_captions_transcribe_not_installed() {
  mk_home; need_py || return 0
  py=$(command -v python3); : > "$HOME/v.mp4"
  PATH=/nonexistent "$py" "$CAP" transcribe --video "$HOME/v.mp4" --out-dir "$HOME/t" > "$HOME/o.txt" 2>&1; rc=$?
  assert_eq "$rc" 4 rc
  grep -q 'brew install whisper-cpp' "$HOME/o.txt" || { echo "  no install hint"; cat "$HOME/o.txt"; exit 1; }
}

test_captions_transcribe_fake_whisper() {
  mk_home; need_py || return 0; need_ff || return 0
  mkdir -p "$HOME/bin"
  cat > "$HOME/bin/whisper-cli" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in -of) p="$2";; -m) m="$2";; -l) l="$2";; esac; shift; done
[ -f "$m" ] || exit 9
echo "lang=$l" > "$FAKE_ARGS"
cat > "$p.json" <<J
{"transcription":[{"offsets":{"from":0,"to":1500},"text":" Hello there."},{"offsets":{"from":1500,"to":3000},"text":"  "},{"offsets":{"from":3000,"to":4200},"text":" Second line."}]}
J
printf '1\n00:00:00,000 --> 00:00:01,500\nHello there.\n' > "$p.srt"
EOF
  chmod +x "$HOME/bin/whisper-cli"; : > "$HOME/model.bin"
  ffmpeg -v error -y -f lavfi -i "sine=frequency=300:duration=2" "$HOME/in.wav"
  FAKE_ARGS="$HOME/t.args" WHISPER_CPP="$HOME/bin/whisper-cli" WHISPER_MODEL="$HOME/model.bin" python3 "$CAP" transcribe --video "$HOME/in.wav" --out-dir "$HOME/t" --lang bn > "$HOME/o.txt" 2>&1 || { cat "$HOME/o.txt"; exit 1; }
  assert_file "$HOME/t/whisper.srt"; assert_eq "$(cat "$HOME/t.args")" "lang=bn" lang
  python3 - "$HOME/t/transcript.json" <<'EOF' || exit 1
import json, sys
t = json.load(open(sys.argv[1]))
assert [(l["text"], l["start"], l["end"]) for l in t["lines"]] == [("Hello there.", 0.0, 1.5), ("Second line.", 3.0, 4.2)], t
EOF
  # a transcript is valid input for render
  fake_chrome "$HOME/bin/chrome"; CHROME="$HOME/bin/chrome" python3 "$CAP" render --parts "$HOME/t/transcript.json" --out-dir "$HOME/cap" >/dev/null 2>&1 || { echo "  render from transcript failed"; exit 1; }
  # a missing model is a clean exit 4
  WHISPER_CPP="$HOME/bin/whisper-cli" WHISPER_MODEL="$HOME/nope.bin" python3 "$CAP" transcribe --video "$HOME/in.wav" --out-dir "$HOME/t2" >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 4 "model missing"
}

# Real Chrome, when one is installed: one frame, 1080 wide, transparent.
test_captions_real_chrome_frame() {
  mk_home; need_py || return 0; need_ff || return 0
  python3 "$CAP" render --out-dir "$HOME/cap" --test-text "ক্ষ ন্দ্র স্ত্র" > "$HOME/o.txt" 2>&1; rc=$?
  [ $rc != 4 ] || { echo "skip: no Chrome installed"; return 0; }
  [ $rc != 124 ] || { echo "skip: $(cat "$HOME/o.txt")"; return 0; }
  [ $rc = 0 ] || { cat "$HOME/o.txt"; exit 1; }
  assert_eq "$(ffprobe -v error -show_entries stream=width,pix_fmt -of csv=p=0 "$HOME/cap/cap00.png")" "1080,rgba" png
}

test_captions_style_values_checked() {
  mk_home; need_py || return 0
  fake_chrome "$HOME/bin/chrome"; CHROME="$HOME/bin/chrome"; export CHROME
  python3 "$CAP" render --out-dir "$HOME/cap" --test-text x --color 'red;}</style><script>x</script>' >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 2 "style injection"
}

test_captions_failed_render_keeps_nothing_stale() {
  mk_home; need_py || return 0
  mkdir -p "$HOME/cap" "$HOME/bin"; echo old > "$HOME/cap/cap00.png"
  printf '#!/bin/sh\nexit 1\n' > "$HOME/bin/chrome"; chmod +x "$HOME/bin/chrome"
  CHROME="$HOME/bin/chrome" python3 "$CAP" render --out-dir "$HOME/cap" --test-text x >/dev/null 2>&1; rc=$?
  assert_eq "$rc" 1 "chrome failed"
  assert_eq "$(cat "$HOME/cap/cap00.png")" old "old file untouched, no success reported"
}

test_captions_transcribe_keeps_existing_wav() {
  mk_home; need_py || return 0; need_ff || return 0
  mkdir -p "$HOME/bin" "$HOME/t"; echo precious > "$HOME/t/audio16k.wav"
  cat > "$HOME/bin/whisper-cli" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in -of) p="$2";; esac; shift; done
echo '{"transcription":[]}' > "$p.json"
EOF
  chmod +x "$HOME/bin/whisper-cli"; : > "$HOME/model.bin"
  ffmpeg -v error -y -f lavfi -i "sine=frequency=300:duration=1" "$HOME/in.wav"
  WHISPER_CPP="$HOME/bin/whisper-cli" WHISPER_MODEL="$HOME/model.bin" python3 "$CAP" transcribe --video "$HOME/in.wav" --out-dir "$HOME/t" >/dev/null 2>&1 || exit 1
  assert_eq "$(cat "$HOME/t/audio16k.wav")" precious "scratch audio is private"
}

test_captions_bad_line_type() {
  mk_home; need_py || return 0
  fake_chrome "$HOME/bin/chrome"; CHROME="$HOME/bin/chrome"; export CHROME
  echo '{"lines":["just text"]}' > "$HOME/p.json"
  python3 "$CAP" render --parts "$HOME/p.json" --out-dir "$HOME/cap" >/dev/null 2>&1; assert_eq "$?" 2 "scalar line"
}
