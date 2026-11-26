#!/bin/sh
. "$(dirname "$0")/lib.sh"
KF="$REPO/keyframes/scripts/keyframes.py"

# Fake engines: write a 1x1 PNG to --output and log their arguments.
# Returns 1 (test skipped) when python3 is missing.
mk_engines() {
  command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; return 1; }
  E="$(mktemp -d)"; B="$E/bin"; mkdir "$B"
  for t in mflux-generate-z-image-turbo mflux-generate-flux2-edit; do
    cat > "$B/$t" <<SH
#!/bin/sh
line="\$0"; out=
for a; do line="\$line [\$a]"; done
echo "\$line" >> "$E/calls.log"
while [ \$# -gt 0 ]; do [ "\$1" = --output ] && out=\$2; shift; done
[ ! -e "\$out" ] || { echo "engine met an existing output" >&2; exit 9; }
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' | { base64 -d 2>/dev/null || base64 -D; } > "\$out"
SH
    chmod +x "$B/$t"
  done
  cat > "$E/ffmpeg" <<SH
#!/bin/sh
echo "ffmpeg \$*" >> "$E/calls.log"
for a; do last=\$a; done
cp "\$5" "\$last"
SH
  chmod +x "$E/ffmpeg"
  MFLUX_BIN_DIR="$B"; FFMPEG_BIN="$E/ffmpeg"; export MFLUX_BIN_DIR FFMPEG_BIN
  OUT="$E/out"
}
kf() { python3 "$KF" "$@"; }
# json <file> <dotted.path>: prints one value from a JSON file.
json() { python3 -c "import json,sys;v=json.load(open(sys.argv[1]))
for k in sys.argv[2].split('.'): v=v[int(k)] if k.isdigit() else v[k]
print(json.dumps(v) if isinstance(v,(list,dict)) else v)" "$@"; }

test_still_arguments_and_sidecar() {
  mk_home; mk_engines || return 0
  printf '# Brand\n\n## Image style\n\nWarm light, muted greens.\n\n## Voice\n\nPlain.\n' > "$E/brand.md"
  kf still --prompt "a cup of tea" --style-file "$E/brand.md" --seed 42 --out-dir "$OUT" --name tea > "$E/log" 2>&1 || { cat "$E/log"; exit 1; }
  assert_file "$OUT/tea.png"; assert_file "$OUT/tea.native.png"; assert_file "$OUT/tea.json"
  c=$(grep mflux-generate-z-image-turbo "$E/calls.log")
  case "$c" in *"[--prompt=a cup of tea Warm light, muted greens.] [--width] [864] [--height] [1536] [--seed] [42]"*) ;; *) echo "bad args: $c"; exit 1;; esac
  case "$c" in *Plain*) echo "other section leaked: $c"; exit 1;; esac
  assert_eq "$(json "$OUT/tea.json" seed)" 42 seed
  assert_eq "$(json "$OUT/tea.json" model)" z-image-turbo model
  assert_eq "$(json "$OUT/tea.json" weight_license)" apache-2.0 license
  assert_eq "$(json "$OUT/tea.json" commercial)" True commercial
  assert_eq "$(json "$OUT/tea.json" final_size)" "[1080, 1920]" size
  grep -q "weights: Tongyi-MAI/Z-Image-Turbo" "$E/log" || { echo "license not printed"; exit 1; }
}

test_random_seed_recorded() {
  mk_home; mk_engines || return 0
  kf still --prompt "a lamp" --native --out-dir "$OUT" --name a >/dev/null || exit 1
  s=$(json "$OUT/a.json" seed)
  case "$s" in ''|*[!0-9]*) echo "seed not a number: $s"; exit 1;; esac
  grep -q -- "\[--seed\] \[$s\]" "$E/calls.log" || { echo "seed not passed"; exit 1; }
}

test_same_face_arguments() {
  mk_home; mk_engines || return 0
  printf x > "$E/r1.png"; printf y > "$E/r2.png"
  kf same-face --ref "$E/r1.png" "$E/r2.png" --prompt "reading in a cafe" --seed 7 --size square --out-dir "$OUT" --name sf >/dev/null || exit 1
  c=$(grep flux2-edit "$E/calls.log")
  case "$c" in *"[--model] [flux2-klein-4b] [--image-paths] [$E/r1.png] [$E/r2.png] [--prompt=The same person as in the reference image. reading in a cafe] [--width] [1024] [--height] [1024] [--seed] [7] [--steps] [4]"*) ;; *) echo "bad args: $c"; exit 1;; esac
  assert_eq "$(json "$OUT/sf.json" refs.1.path)" "$E/r2.png" ref
  assert_eq "$(json "$OUT/sf.json" refs.0.sha256 | wc -c | tr -d ' ')" 65 sha
  assert_eq "$(json "$OUT/sf.json" weights_repo)" black-forest-labs/FLUX.2-klein-4B repo
  grep -q "^ffmpeg" "$E/calls.log" || exit 1
}

test_noncommercial_refused_unless_flag() {
  mk_home; mk_engines || return 0
  printf x > "$E/r1.png"
  kf same-face --model flux2-klein-9b --ref "$E/r1.png" --prompt "p" --native --out-dir "$OUT" > "$E/log" 2>&1; rc=$?
  assert_eq "$rc" 3 "exit code"
  grep -q "refused" "$E/log" || exit 1
  assert_no "$E/calls.log"; assert_no "$OUT"
  kf same-face --model flux2-klein-9b --noncommercial-ok --ref "$E/r1.png" --prompt "p" --native --out-dir "$OUT" --name nc >/dev/null || exit 1
  assert_eq "$(json "$OUT/nc.json" commercial)" False commercial
  assert_eq "$(json "$OUT/nc.json" noncommercial_ok_flag)" True flag
}

test_sizes() {
  mk_home; mk_engines || return 0
  kf still --prompt p --size square --out-dir "$OUT" --name sq >/dev/null || exit 1
  grep -q -- "\[--width\] \[1024\] \[--height\] \[1024\]" "$E/calls.log" || exit 1
  grep -q "scale=1080:1080" "$E/calls.log" || exit 1
  kf still --prompt p --size 1000x700 --native --out-dir "$OUT" --name cu >/dev/null || exit 1
  grep -q -- "\[--width\] \[1008\] \[--height\] \[704\]" "$E/calls.log" || { cat "$E/calls.log"; exit 1; }
  assert_eq "$(json "$OUT/cu.json" final_size)" "[1008, 704]" native
  assert_no "$OUT/cu.native.png"
  kf still --prompt p --size 1008x704 --out-dir "$OUT" --name ex >/dev/null || exit 1
  assert_no "$OUT/ex.native.png"
  kf still --prompt p --size huge --out-dir "$OUT" >/dev/null 2>&1; assert_eq "$?" 2 "bad size"
  kf still --prompt p --size reel --out-dir "$OUT" --name r >/dev/null || exit 1
  grep -q "scale=1080:1920:force_original_aspect_ratio=increase" "$E/calls.log" || exit 1
}

test_missing_engine_and_ffmpeg() {
  mk_home; mk_engines || return 0
  MFLUX_BIN_DIR="$E/nowhere" kf still --prompt p --out-dir "$OUT" > "$E/log" 2>&1; rc=$?
  assert_eq "$rc" 4 "no engine"
  grep -q "mflux-generate-z-image-turbo" "$E/log" || exit 1
  grep -q "MFLUX_BIN_DIR" "$E/log" || exit 1
  FFMPEG_BIN="$E/nope" kf still --prompt p --out-dir "$OUT" > "$E/log" 2>&1; assert_eq "$?" 4 "no ffmpeg"
  kf still --out-dir "$OUT" >/dev/null 2>&1; assert_eq "$?" 2 "no prompt"
}

test_no_overwrite_without_flag() {
  mk_home; mk_engines || return 0
  kf still --prompt p --native --seed 1 --out-dir "$OUT" --name x >/dev/null || exit 1
  kf still --prompt p --native --seed 1 --out-dir "$OUT" --name x >/dev/null 2>&1; assert_eq "$?" 1 "exists"
  kf still --prompt p --native --seed 1 --out-dir "$OUT" --name x --overwrite >/dev/null || exit 1
}

test_owner_out_dir() {
  mk_home; mk_engines || return 0
  kf still --prompt p --native --seed 1 --owner lumen-tea --name x > "$E/log" || exit 1
  assert_file "$KAITO_HOME/owners/lumen-tea/studio/keyframes/x.png"
}

test_licenses_listed() {
  mk_home
  command -v python3 >/dev/null 2>&1 || { echo "skip: python3 missing"; return 0; }
  kf licenses | grep -q "Tongyi-MAI/Z-Image-Turbo.*apache-2.0.*commercial=yes" || exit 1
  kf licenses | grep -q "FLUX.2-klein-9B.*commercial=no" || exit 1
}

test_score_without_dlib_exits_4() {
  mk_home; mk_engines || return 0
  printf x > "$E/a.png"
  printf '#!/bin/sh\nexit 1\n' > "$E/nodlib"; chmod +x "$E/nodlib"
  LIKENESS_PYTHON="$E/nodlib" kf score --ref "$E/a.png" --candidate "$E/a.png" > "$E/log" 2>&1; rc=$?
  assert_eq "$rc" 4 "exit"
  grep -q "dlib" "$E/log" && grep -q "LIKENESS_PYTHON" "$E/log" || { cat "$E/log"; exit 1; }
  LIKENESS_PYTHON="$E/missing" kf score --ref "$E/a.png" --candidate "$E/a.png" >/dev/null 2>&1; assert_eq "$?" 4 "no python"
}

test_score_with_fake_python() {
  mk_home; mk_engines || return 0
  printf x > "$E/a.png"; printf y > "$E/b.png"
  cat > "$E/fakepy" <<SH
#!/bin/sh
case "\$*" in *"import dlib"*) echo keyframes-likeness-ok; exit 0;; esac
echo "\$*" >> "$E/py.log"
echo '{"refs_used": ["a"], "refs_noface": [], "mean": 0.21, "min": 0.18}'
SH
  chmod +x "$E/fakepy"
  LIKENESS_PYTHON="$E/fakepy" kf score --ref "$E/a.png" --candidate "$E/b.png" > "$E/log" 2>&1 || { cat "$E/log"; exit 1; }
  grep -q "mean 0.210.*min 0.180.*same person" "$E/log" || { cat "$E/log"; exit 1; }
  grep -q -- "$E/a.png --candidate $E/b.png" "$E/py.log" || { cat "$E/py.log"; exit 1; }
  cat > "$E/fakeno" <<SH
#!/bin/sh
case "\$*" in *"import dlib"*) echo keyframes-likeness-ok; exit 0;; esac
echo '{"refs_used": [], "refs_noface": ["a"], "noface": true}'
SH
  chmod +x "$E/fakeno"
  LIKENESS_PYTHON="$E/fakeno" kf score --ref "$E/a.png" --candidate "$E/b.png" >/dev/null 2>&1; assert_eq "$?" 1 "noface"
}

test_score_probe_needs_marker() {
  mk_home; mk_engines || return 0
  printf x > "$E/a.png"
  # an import that "succeeds" without importing (face_recognition quits quietly when its models are missing)
  printf '#!/bin/sh\nexit 0\n' > "$E/quiet"; chmod +x "$E/quiet"
  LIKENESS_PYTHON="$E/quiet" kf score --ref "$E/a.png" --candidate "$E/a.png" >/dev/null 2>&1; assert_eq "$?" 4 "no marker"
}

test_overwrite_replaces_and_engine_never_sees_existing_file() {
  mk_home; mk_engines || return 0
  kf still --prompt p --native --seed 1 --out-dir "$OUT" --name x >/dev/null || exit 1
  kf still --prompt p --native --seed 2 --out-dir "$OUT" --name x --overwrite >/dev/null || exit 1
  assert_eq "$(json "$OUT/x.json" seed)" 2 "sidecar matches the new run"
}

test_failed_run_leaves_nothing() {
  mk_home; mk_engines || return 0
  printf '#!/bin/sh\nexit 7\n' > "$MFLUX_BIN_DIR/mflux-generate-z-image-turbo"
  kf still --prompt p --seed 1 --out-dir "$OUT" --name x > "$E/log" 2>&1; assert_eq "$?" 1 "engine failed"
  assert_no "$OUT/x.png"; assert_no "$OUT/x.json"; assert_no "$OUT/x.native.png"
}

test_unsafe_names_refused() {
  mk_home; mk_engines || return 0
  kf still --prompt p --native --out-dir "$OUT" --name ../evil >/dev/null 2>&1; assert_eq "$?" 2 "name"
  kf still --prompt p --native --owner lumen-tea --job /tmp/x >/dev/null 2>&1; assert_eq "$?" 2 "job"
  kf still --prompt p --native --owner ../x >/dev/null 2>&1; assert_eq "$?" 2 "owner"
  kf still --prompt p --size 0x700 --out-dir "$OUT" >/dev/null 2>&1; assert_eq "$?" 2 "zero size"
  kf still --prompt - --native --out-dir "$OUT" >/dev/null 2>&1; assert_eq "$?" 2 "stdin prompt"
  assert_no "$E/calls.log"
}

test_prompt_with_dashes_stays_one_argument() {
  mk_home; mk_engines || return 0
  kf still --prompt "--help me" --native --seed 3 --out-dir "$OUT" --name d >/dev/null || exit 1
  grep -q -F "[--prompt=--help me]" "$E/calls.log" || { cat "$E/calls.log"; exit 1; }
}
