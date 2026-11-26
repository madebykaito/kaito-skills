#!/bin/sh
# local-video: the ComfyUI client and local_video.py, against a fake ComfyUI. No GPU, no models, no real lock.
. "$(dirname "$0")/lib.sh"
. "$TESTS_DIR/stubs/fake-comfy.sh"
LV="$REPO/local-video/scripts/local_video.py"
WF="$REPO/local-video/workflows"
H3_TEMPLATES="$WF/h3_t2v.json,$WF/h3_i2v.json,$WF/seedvr2_upscale.json"

test_lv_templates_are_valid() {
  have_py || return 0
  for f in "$WF"/*.json "$REPO"/music/workflows/*.json; do
    python3 - "$f" <<'E' || { echo "  bad template: $f"; exit 1; }
import json, sys
t = json.load(open(sys.argv[1]))
g = t["graph"]
assert t["meta"]["need_gb"] > 0 and t["meta"]["models"], "meta"
for nid, n in g.items():
    assert "class_type" in n and "inputs" in n, nid
    for v in n["inputs"].values():
        if isinstance(v, list) and len(v) == 2 and isinstance(v[1], int):
            assert v[0] in g, "dangling link %s -> %s" % (nid, v[0])
E
  done
}

test_lv_t2v_frees_before_and_after_and_downloads() {
  have_py || return 0
  mk_home; start_fake --have-from "$H3_TEMPLATES"
  out="$HOME/out"
  python3 "$LV" t2v --prompt "a kettle on a stove" --license-ok --settle 0 --out-dir "$out" --name clip > "$HOME/res" 2> "$HOME/err" || { cat "$HOME/err"; exit 1; }
  assert_file "$out/clip.mp4"
  assert_file "$out/clip.json"
  grep -q "^video=$out/clip.mp4$" "$HOME/res" || { echo "  no video= line"; cat "$HOME/res"; exit 1; }
  assert_eq "$(python3 -c "import json;print(json.load(open('$out/clip.json'))['engine'])")" h3 sidecar
  [ "$(log_count /prompt)" = 1 ] || { echo "  want one prompt"; exit 1; }
  f1=$(log_first /free); p1=$(log_first /prompt); fl=$(log_last /free)
  [ -n "$f1" ] && [ "$f1" -lt "$p1" ] || { echo "  /free did not come before /prompt"; cat "$FAKELOG"; exit 1; }
  [ "$fl" -gt "$p1" ] || { echo "  no /free after the run"; exit 1; }
  grep -q 'a kettle on a stove' "$FAKELOG" || { echo "  prompt text not substituted"; exit 1; }
  assert_no "$HOME/heavy.lock"
}

test_lv_free_between_two_models() {
  have_py || return 0
  mk_home; start_fake --have-from "$H3_TEMPLATES"
  out="$HOME/out"
  printf 'fake' > "$HOME/in.mp4"
  python3 "$LV" t2v --prompt one --license-ok --settle 0 --out-dir "$out" --name a > /dev/null 2>&1 || exit 1
  python3 "$LV" upscale --video "$HOME/in.mp4" --settle 0 --out-dir "$out" --name b > /dev/null 2> "$HOME/err" || { cat "$HOME/err"; exit 1; }
  # two prompts, and a /free between them and one before each
  [ "$(log_count /prompt)" = 2 ] || { echo "  want two prompts"; exit 1; }
  [ "$(log_count /free)" = 4 ] || { echo "  want four /free calls, got $(log_count /free)"; cat "$FAKELOG"; exit 1; }
  awk -F: '/"p": "\/prompt"/ {n++; if (n == 2) exit} /"p": "\/free"/ {if (n == 1) between++} END {exit between ? 0 : 1}' "$FAKELOG" || { echo "  no /free between the two models"; exit 1; }
  grep -q '"name": "in.mp4"' "$FAKELOG" || { echo "  video was not uploaded"; exit 1; }
}

test_lv_h3_needs_license_ok() {
  have_py || return 0
  mk_home; start_fake --have-from "$H3_TEMPLATES"
  python3 "$LV" t2v --prompt x --settle 0 --out-dir "$HOME/out" > /dev/null 2> "$HOME/err"; rc=$?
  assert_eq "$rc" 3 exit
  grep -q "MiniMax H3 Community License" "$HOME/err" || { echo "  licence text not printed"; cat "$HOME/err"; exit 1; }
  grep -q -- "--license-ok" "$HOME/err" || { echo "  does not say what to pass"; exit 1; }
  [ "$(log_count /prompt)" = 0 ] || { echo "  ran without --license-ok"; exit 1; }
}

test_lv_low_memory_refuses_with_numbers() {
  have_py || return 0
  mk_home; start_fake --have-from "$H3_TEMPLATES" --ram-free-gb 4 --ram-total-gb 48
  python3 "$LV" t2v --prompt x --license-ok --settle 0 --out-dir "$HOME/out" > /dev/null 2> "$HOME/err"; rc=$?
  assert_eq "$rc" 3 exit
  grep -q "4.0 GB free of 48.0 GB" "$HOME/err" || { echo "  numbers missing"; cat "$HOME/err"; exit 1; }
  grep -q "needs 26.0 GB" "$HOME/err" || { echo "  need missing"; cat "$HOME/err"; exit 1; }
  [ "$(log_count /prompt)" = 0 ] || { echo "  started anyway"; exit 1; }
  assert_no "$HOME/heavy.lock"
}

test_lv_high_need_override_simulates_low_memory() {
  have_py || return 0
  mk_home; start_fake --have-from "$H3_TEMPLATES" --ram-free-gb 40
  python3 "$LV" t2v --prompt x --license-ok --need-gb 999 --settle 0 --out-dir "$HOME/out" > /dev/null 2> "$HOME/err"; rc=$?
  assert_eq "$rc" 3 exit
  grep -q "needs 999.0 GB" "$HOME/err" || { cat "$HOME/err"; exit 1; }
  [ "$(log_count /prompt)" = 0 ] || exit 1
}

test_lv_missing_ltx_weights_is_a_clean_error() {
  have_py || return 0
  mk_home; start_fake --have-from "$H3_TEMPLATES"
  ffmpeg -v error -y -f lavfi -i color=c=red:s=64x64 -frames:v 1 "$HOME/s.png" 2>/dev/null || printf 'png' > "$HOME/s.png"
  python3 "$LV" i2v --engine ltx --image "$HOME/s.png" --prompt x --settle 0 --out-dir "$HOME/out" > /dev/null 2> "$HOME/err"; rc=$?
  assert_eq "$rc" 4 exit
  grep -q "missing engine" "$HOME/err" || { cat "$HOME/err"; exit 1; }
  grep -q "ltx-video" "$HOME/err" || { echo "  does not name the file"; exit 1; }
  [ "$(log_count /prompt)" = 0 ] || exit 1
  [ "$(log_count /free)" = 0 ] || { echo "  freed models for an engine that cannot run"; exit 1; }
}

test_lv_missing_node_pack_is_a_clean_error() {
  have_py || return 0
  mk_home; start_fake --have-from "$H3_TEMPLATES" --missing-node UnetLoaderGGUF
  python3 "$LV" t2v --prompt x --license-ok --settle 0 --out-dir "$HOME/out" > /dev/null 2> "$HOME/err"; rc=$?
  assert_eq "$rc" 4 exit
  grep -q "UnetLoaderGGUF" "$HOME/err" || { cat "$HOME/err"; exit 1; }
}

test_lv_ltx_runs_when_weights_exist() {
  have_py || return 0
  mk_home; start_fake --have-from "$H3_TEMPLATES" --have ltx-video-2b-v0.9.5.safetensors --have t5xxl_fp16.safetensors
  printf 'png' > "$HOME/s.png"
  python3 "$LV" i2v --engine ltx --image "$HOME/s.png" --prompt "slow pan" --seconds 4 --settle 0 --out-dir "$HOME/out" --name l > /dev/null 2> "$HOME/err" || { cat "$HOME/err"; exit 1; }
  assert_file "$HOME/out/l.mp4"
  grep -q '"frames": 97\|"length": 97' "$FAKELOG" || { echo "  frame count wrong"; exit 1; }
}

test_lv_i2v_uploads_the_still() {
  have_py || return 0
  mk_home; start_fake --have-from "$H3_TEMPLATES"
  printf 'png' > "$HOME/still.png"
  python3 "$LV" i2v --image "$HOME/still.png" --prompt "steam rises" --license-ok --seconds 3 --seed 5 --settle 0 --out-dir "$HOME/out" --name v > /dev/null 2> "$HOME/err" || { cat "$HOME/err"; exit 1; }
  grep -q '"name": "still.png"' "$FAKELOG" || { echo "  still not uploaded"; exit 1; }
  python3 - "$FAKELOG" <<'E' || exit 1
import json, sys
p = [json.loads(l) for l in open(sys.argv[1]) if '"/prompt"' in l][0]["prompt"]
assert p["still"]["inputs"]["image"] == "still.png", p["still"]
assert p["seconds"]["inputs"]["value"] == 3.0
assert p["noise"]["inputs"]["noise_seed"] == 5
assert p["sigmas"]["inputs"]["steps"] == 8 and p["sampler"]["inputs"]["sampler_name"] == "er_sde"
E
}

test_lv_waits_for_the_heavy_lock() {
  have_py || return 0
  mk_home; start_fake --have-from "$H3_TEMPLATES"
  mkdir "$KAITO_HEAVY_LOCK"
  python3 "$LV" t2v --prompt x --license-ok --settle 0 --lock-timeout 1 --out-dir "$HOME/out" > /dev/null 2> "$HOME/err"; rc=$?
  assert_eq "$rc" 3 exit
  grep -q "waiting for the heavy-model lock" "$HOME/err" || { cat "$HOME/err"; exit 1; }
  [ -d "$KAITO_HEAVY_LOCK" ] || { echo "  removed a lock it does not own"; exit 1; }
  # released while we wait: the run goes through
  ( sleep 1; rmdir "$KAITO_HEAVY_LOCK" ) &
  python3 "$LV" t2v --prompt x --license-ok --settle 0 --lock-timeout 20 --out-dir "$HOME/out" --name w > /dev/null 2> "$HOME/err" || { cat "$HOME/err"; exit 1; }
  assert_file "$HOME/out/w.mp4"
  assert_no "$KAITO_HEAVY_LOCK"
}

test_lv_busy_comfy_is_not_loaded_twice() {
  have_py || return 0
  mk_home; start_fake --have-from "$H3_TEMPLATES" --busy
  python3 "$LV" t2v --prompt x --license-ok --settle 0 --out-dir "$HOME/out" > /dev/null 2> "$HOME/err"; rc=$?
  assert_eq "$rc" 3 exit
  [ "$(log_count /free)" = 0 ] || { echo "  freed models under a running job"; exit 1; }
}

test_lv_failed_job_exits_1_and_still_frees() {
  have_py || return 0
  mk_home; start_fake --have-from "$H3_TEMPLATES" --fail-job
  python3 "$LV" t2v --prompt x --license-ok --settle 0 --out-dir "$HOME/out" > /dev/null 2> "$HOME/err"; rc=$?
  assert_eq "$rc" 1 exit
  grep -q boom "$HOME/err" || { cat "$HOME/err"; exit 1; }
  [ "$(log_last /free)" -gt "$(log_last /prompt)" ] || { echo "  no /free after the failure"; exit 1; }
  assert_no "$KAITO_HEAVY_LOCK"
}

test_lv_no_comfy_is_exit_4() {
  have_py || return 0
  mk_home; comfy_env
  COMFY_URL=http://127.0.0.1:1; export COMFY_URL
  python3 "$LV" t2v --prompt x --license-ok --settle 0 --out-dir "$HOME/out" > /dev/null 2> "$HOME/err"; rc=$?
  assert_eq "$rc" 4 exit
  assert_no "$KAITO_HEAVY_LOCK"
}

test_lv_comfy_cli_probe_reports_memory() {
  have_py || return 0
  mk_home; start_fake --ram-free-gb 12 --ram-total-gb 48
  out=$(python3 "$REPO/local-video/scripts/comfy.py" probe) || exit 1
  case "$out" in *'"free_gb": 12.0'*) ;; *) echo "  $out"; exit 1;; esac
}

test_lv_kenburns_plan_from_parts() {
  have_py || return 0
  mk_home
  printf 'png' > "$HOME/a.png"; printf 'png' > "$HOME/b.png"
  printf '{"parts":[{"duration":2.5},{"start":10,"end":13.25}]}' > "$HOME/parts.json"
  printf '[{"image":"a.png","move":"pan_left","line":0},{"image":"b.png","line":1,"share":0.5}]' > "$HOME/shots.json"
  python3 "$LV" kenburns --shots "$HOME/shots.json" --parts "$HOME/parts.json" --dry-run > "$HOME/plan" || exit 1
  python3 - "$HOME/plan" <<'E' || exit 1
import json, sys
p = json.load(open(sys.argv[1]))["shots"]
assert [s["seconds"] for s in p] == [2.5, 1.625], p
assert [s["move"] for s in p] == ["pan_left", "push_in"], p
E
  python3 "$LV" kenburns --image "$HOME/a.png" --dry-run > /dev/null 2>&1; assert_eq "$?" 2 "needs a duration"
}

test_lv_kenburns_renders_with_ffmpeg() {
  command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1 || { echo "skip: ffmpeg is not installed"; return 0; }
  have_py || return 0
  mk_home
  ffmpeg -v error -y -f lavfi -i testsrc2=size=640x640:rate=1 -frames:v 1 "$HOME/s.png" || exit 1
  python3 "$LV" kenburns --image "$HOME/s.png" --duration 2 --move push_in --size 270x480 --fps 24 --out-dir "$HOME/out" --name k > "$HOME/res" || exit 1
  assert_file "$HOME/out/k.mp4"
  assert_eq "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,nb_frames -of csv=p=0 "$HOME/out/k.mp4")" "270,480,48" probe
  assert_eq "$(python3 -c "import json;print(json.load(open('$HOME/out/k.json'))['seconds'])")" 2.0 sidecar
}

test_lv_comfy_cli_run_also_needs_license_ok() {
  have_py || return 0
  mk_home; start_fake --have-from "$H3_TEMPLATES"
  python3 "$REPO/local-video/scripts/comfy.py" run "$WF/h3_t2v.json" --out-dir "$HOME/out" --param prompt=x > /dev/null 2> "$HOME/err"; rc=$?
  assert_eq "$rc" 3 exit
  [ "$(log_count /prompt)" = 0 ] || exit 1
}

test_lv_no_secrets_or_private_names_in_the_skill() {
  if grep -rIlE -i 'aura-creators|aura logic|c1x|nolen' "$REPO/local-video" "$REPO/music"; then echo "  private name in a shipped file"; exit 1; fi
  return 0
}
