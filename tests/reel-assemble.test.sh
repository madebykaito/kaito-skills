#!/bin/sh
. "$(dirname "$0")/lib.sh"
test_preflight_rejects_96k() {
  mk_home
  command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || { echo 'skip: ffmpeg missing'; return; }
  ffmpeg -v error -f lavfi -i color=s=1080x1920:r=25:d=3 -f lavfi -i sine=sample_rate=96000:duration=3 -c:v libx264 -profile:v high -pix_fmt yuv420p -c:a aac -ac 2 -ar 96000 -movflags +faststart -shortest "$HOME/bad.mp4"
  assert_file "$REPO/reel-assemble/scripts/media-spec.py"
  if python3 "$REPO/reel-assemble/scripts/media-spec.py" check "$HOME/bad.mp4" --target ig-reels 2>"$HOME/error"; then echo 'accepted 96 kHz'; return 1; fi
  grep '48 kHz' "$HOME/error" >/dev/null
}
test_assemble_fixture() {
  mk_home
  command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || { echo 'skip: ffmpeg missing'; return; }
  ffmpeg -v error -f lavfi -i testsrc2=s=180x320:r=25:d=4 -c:v libx264 "$HOME/shot.mp4"
  ffmpeg -v error -f lavfi -i sine=frequency=440:duration=4 -ar 48000 "$HOME/voice.wav"
  ffmpeg -v error -f lavfi -i sine=frequency=220:duration=4 "$HOME/bed.wav"
  printf '{"voice":"voice.wav","duration":4,"lines":[]}' > "$HOME/parts.json"
  printf '{"y":1380,"captions":[]}' > "$HOME/captions.json"
  python3 "$REPO/reel-assemble/scripts/reel-assemble.py" --shots "$HOME/shot.mp4" --parts "$HOME/parts.json" --captions "$HOME/captions.json" --bed "$HOME/bed.wav" --out "$HOME/out.mp4" || return 1
  python3 "$REPO/reel-assemble/scripts/media-spec.py" check "$HOME/out.mp4" --target ig-reels
}

test_manifest_media_must_be_local_regular_files() {
  mk_home
  mkdir -p "$HOME/job/not-a-file"
  : > "$HOME/job/voice.wav"
  cat > "$HOME/fake-ffmpeg" <<'SH'
#!/bin/sh
: > "$HOME/ffmpeg-ran"
SH
  chmod +x "$HOME/fake-ffmpeg"
  export FFMPEG_BIN="$HOME/fake-ffmpeg"
  assemble() {
    python3 "$REPO/reel-assemble/scripts/reel-assemble.py" --shots shot.mp4 --parts "$HOME/job/parts.json" \
      --captions "$HOME/job/captions.json" --bed bed.wav --out "$HOME/out.mp4" > "$HOME/stdout" 2> "$HOME/error"
  }
  printf '{"y":1380,"captions":[]}' > "$HOME/job/captions.json"
  for voice in "$HOME/job/voice.wav" '../missing.wav' 'not-a-file'; do
    printf '{"voice":"%s","duration":4}' "$voice" > "$HOME/job/parts.json"
    assemble; rc=$?
    assert_eq "$rc" 1 voice
    grep -q 'manifest media must be a relative regular file inside its directory' "$HOME/error" || exit 1
    assert_no "$HOME/ffmpeg-ran"
  done
  printf '{"voice":"voice.wav","duration":4}' > "$HOME/job/parts.json"
  printf '{"y":1380,"captions":[{"start":0,"end":1,"file":"not-a-file"}]}' > "$HOME/job/captions.json"
  assemble; rc=$?
  assert_eq "$rc" 1 caption
  grep -q 'manifest media must be a relative regular file inside its directory' "$HOME/error" || exit 1
  assert_no "$HOME/ffmpeg-ran"
  if ! skip_on_win "symlinks"; then
    : > "$HOME/placeholder.png"
    ln -s "$HOME/placeholder.png" "$HOME/job/caption.png" || exit 1
    printf '{"y":1380,"captions":[{"start":0,"end":1,"file":"caption.png"}]}' > "$HOME/job/captions.json"
    assemble; rc=$?
    assert_eq "$rc" 1 caption-symlink
    grep -q 'manifest media must be a relative regular file inside its directory' "$HOME/error" || exit 1
    assert_no "$HOME/ffmpeg-ran"
    rm "$HOME/job/caption.png"
  fi
  : > "$HOME/job/caption.png"
  printf '{"y":1380,"captions":[{"start":0,"end":1,"file":"caption.png"}]}' > "$HOME/job/captions.json"
  assemble || exit 1
  assert_file "$HOME/ffmpeg-ran"
}
