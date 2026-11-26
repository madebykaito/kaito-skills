#!/bin/sh
# music: ACE-Step takes through a fake ComfyUI. No GPU, no models, no real lock.
. "$(dirname "$0")/lib.sh"
. "$TESTS_DIR/stubs/fake-comfy.sh"
MU="$REPO/music/scripts/music.py"
TPL="$REPO/music/workflows/acestep_instrumental.json"

takes_of() {  # print "seed|tags" for each /prompt in the fake's log
  python3 - "$FAKELOG" <<'E'
import json, sys
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r.get("p") == "/prompt":
        t = r["prompt"]["text"]["inputs"]
        k = r["prompt"]["sample"]["inputs"]
        assert t["seed"] == k["seed"], "text and sampler seeds differ"
        print("%s|%s" % (t["seed"], t["tags"]))
E
}

test_music_dry_run_takes_differ() {
  have_py || return 0
  mk_home
  python3 "$MU" --style "lo-fi, soft keys" --takes 4 --seconds 30 --dry-run > "$HOME/plan" || exit 1
  python3 - "$HOME/plan" <<'E' || exit 1
import json, sys
p = json.load(open(sys.argv[1]))
t = p["takes"]
assert len(t) == 4
assert len({x["seed"] for x in t}) == 4, "seeds repeat"
assert len({x["tags"] for x in t}) == 4, "styles repeat"
assert all(x["tags"].startswith("lo-fi, soft keys") and "instrumental" in x["tags"] for x in t)
E
}

test_music_custom_variants() {
  have_py || return 0
  mk_home
  python3 "$MU" --style base --takes 2 --variants "sitar|marimba" --dry-run > "$HOME/plan" || exit 1
  grep -q 'base, sitar' "$HOME/plan" && grep -q 'base, marimba' "$HOME/plan" || { cat "$HOME/plan"; exit 1; }
}

test_music_takes_run_with_distinct_seeds_and_styles() {
  have_py || return 0
  mk_home; start_fake --have-from "$TPL"
  python3 "$MU" --style "calm ambient" --takes 3 --seconds 12 --seed 100 --settle 0 --out-dir "$HOME/out" --name bed > "$HOME/res" 2> "$HOME/err" || { cat "$HOME/err"; exit 1; }
  for n in 1 2 3; do
    assert_file "$HOME/out/bed-take$n.wav"
    assert_file "$HOME/out/bed-take$n.json"
  done
  takes_of > "$HOME/takes"
  assert_eq "$(wc -l < "$HOME/takes" | tr -d ' ')" 3 prompts
  assert_eq "$(cut -d'|' -f1 "$HOME/takes" | sort -u | wc -l | tr -d ' ')" 3 "distinct seeds"
  assert_eq "$(cut -d'|' -f2 "$HOME/takes" | sort -u | wc -l | tr -d ' ')" 3 "distinct styles"
  assert_eq "$(head -1 "$HOME/takes" | cut -d'|' -f1)" 100 "take 1 seed"
  python3 - "$HOME/out" <<'E' || exit 1
import json, sys, wave
d = sys.argv[1]
seen = set()
for n in (1, 2, 3):
    j = json.load(open("%s/bed-take%d.json" % (d, n)))
    assert j["engine"] == "acestep" and j["sample_rate"] == 48000 and j["channels"] == 2 and j["vocals"] is False, j
    assert j["seconds_requested"] == 12
    seen.add((j["seed"], j["tags"]))
    with wave.open("%s/bed-take%d.wav" % (d, n)) as w:
        assert w.getframerate() == 48000
assert len(seen) == 3
E
  # one model load for three takes: one /free before the first prompt, one after the last
  assert_eq "$(log_count /free)" 2 "free calls"
  [ "$(log_first /free)" -lt "$(log_first /prompt)" ] || { echo "  /free not before the first take"; exit 1; }
  [ "$(log_last /free)" -gt "$(log_last /prompt)" ] || { echo "  /free not after the last take"; exit 1; }
  assert_no "$KAITO_HEAVY_LOCK"
}

test_music_converts_other_sample_rates_to_48k() {
  command -v ffmpeg >/dev/null 2>&1 || { echo "skip: ffmpeg is not installed"; return 0; }
  have_py || return 0
  mk_home; start_fake --have-from "$TPL" --audio-rate 44100
  python3 "$MU" --seconds 8 --settle 0 --out-dir "$HOME/out" --name c > /dev/null 2> "$HOME/err" || { cat "$HOME/err"; exit 1; }
  assert_eq "$(python3 -c "import json;print(json.load(open('$HOME/out/c-take1.json'))['sample_rate'])")" 48000 rate
}

test_music_low_memory_exits_3_with_numbers() {
  have_py || return 0
  mk_home; start_fake --have-from "$TPL" --ram-free-gb 5 --ram-total-gb 48
  python3 "$MU" --seconds 30 --settle 0 --out-dir "$HOME/out" > /dev/null 2> "$HOME/err"; rc=$?
  assert_eq "$rc" 3 exit
  grep -q "5.0 GB free of 48.0 GB" "$HOME/err" || { cat "$HOME/err"; exit 1; }
  grep -q "needs 14.0 GB" "$HOME/err" || { cat "$HOME/err"; exit 1; }
  assert_eq "$(log_count /prompt)" 0 "no prompt"
}

test_music_missing_model_is_exit_4() {
  have_py || return 0
  mk_home; start_fake
  python3 "$MU" --seconds 30 --settle 0 --out-dir "$HOME/out" > /dev/null 2> "$HOME/err"; rc=$?
  assert_eq "$rc" 4 exit
  grep -q "ace_step_1.5_turbo_aio.safetensors" "$HOME/err" || { cat "$HOME/err"; exit 1; }
}

test_music_usage_errors() {
  have_py || return 0
  mk_home
  python3 "$MU" --seconds 2 --dry-run > /dev/null 2>&1; assert_eq "$?" 2 "too short"
  python3 "$MU" --takes 0 --dry-run > /dev/null 2>&1; assert_eq "$?" 2 "no takes"
}
