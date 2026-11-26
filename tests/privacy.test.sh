#!/bin/sh
. "$(dirname "$0")/lib.sh"
SCAN="$REPO/tools/privacy-scan.mjs"
OWNERS="$REPO/tests/fixtures/business/owners"

# home: a temp home with no denylist, whatever the caller's environment holds.
home() { mk_home; unset KAITO_PRIVACY_DENYLIST; }
# scan <folder>: run the scanner on a folder with the generic patterns only.
scan() { node "$SCAN" "$1" --no-denylist 2>&1; }
# Read the marker from a local fixture denylist, as the scanner does.
denylist_fixture() {
  printf 'private-fixture-%s\n' "$$" > "$1"
  IFS= read -r term < "$1"
}
# expect_hit <folder> <rule>: the scan must exit 1 and report the rule.
expect_hit() {
  out=$(scan "$1"); rc=$?
  [ "$rc" = 1 ] || { echo "  want exit 1, got $rc: $out"; exit 1; }
  case "$out" in *": $2: "*) ;; *) echo "  rule $2 not reported: $out"; exit 1;; esac
}

test_clean_folder_passes() {
  home
  d=$(mktemp -d); printf 'plain text, mail ira@example.com, tea at 850 rupees\n' > "$d/a.md"
  out=$(scan "$d") || { echo "  $out"; exit 1; }
  assert_eq "$out" "privacy ok" clean
}

test_repo_passes_generic() {
  home   # a temp home has no denylist: generic patterns only, as in CI
  out=$(cd "$REPO" && node tools/privacy-scan.mjs 2>&1) || { echo "  $out"; exit 1; }
  assert_eq "$out" "privacy ok" repo
}

test_planted_key_fails_and_is_masked() {
  home
  d=$(mktemp -d)
  key=$(printf 'sk-%s' "Ab12Cd34Ef56Gh78Ij90Kl12Mn34")
  printf 'token = "%s"\n' "$key" > "$d/conf.txt"
  expect_hit "$d" key-openai
  out=$(scan "$d")
  case "$out" in *"conf.txt:1: key-openai: sk-***"*) ;; *) echo "  bad mask: $out"; exit 1;; esac
  case "$out" in *Ab12Cd34*) echo "  secret printed: $out"; exit 1;; esac
}

test_planted_github_and_aws_keys_fail() {
  home
  d=$(mktemp -d)
  printf 'a=%s%s\n' "ghp_" "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8" > "$d/g.txt"
  expect_hit "$d" key-github
  d=$(mktemp -d)
  printf 'a=%s%s\n' "AKIA" "ABCDEFGHIJKLMNOP" > "$d/a.txt"
  expect_hit "$d" key-aws
}

test_planted_email_fails() {
  home
  d=$(mktemp -d)
  printf 'write to %s@%s\n' "founder" "fixture.invalid" > "$d/mail.md"
  expect_hit "$d" email
  out=$(scan "$d")
  case "$out" in *"mail.md:1: email: fou***"*) ;; *) echo "  bad mask: $out"; exit 1;; esac
  case "$out" in *fixture.invalid*) echo "  email printed: $out"; exit 1;; esac
}

test_allowed_emails_pass() {
  home
  d=$(mktemp -d)
  printf 'a@example.com b@example.org noreply@anything.dev kaito@madebykaito.com\n' > "$d/ok.md"
  out=$(scan "$d") || { echo "  $out"; exit 1; }
  assert_eq "$out" "privacy ok" allowed
}

test_phone_gstin_pan_fail() {
  home
  d=$(mktemp -d)
  printf 'call %s%s\n' "+91 98" "765 43210" > "$d/p.md"
  expect_hit "$d" phone
  d=$(mktemp -d)
  printf 'gst %s%s\n' "27AAPFU0939F1" "ZV" > "$d/g.md"
  expect_hit "$d" gstin
  d=$(mktemp -d)
  printf 'pan %s%s\n' "AAPFU0939" "F" > "$d/n.md"
  expect_hit "$d" pan
  d=$(mktemp -d)
  printf 'gst 19ABCDE1234F1Z5 pan ABCDE1234F\n' > "$d/fake.md"
  out=$(scan "$d") || { echo "  fake gstin must pass: $out"; exit 1; }
}

test_secret_next_to_key_word_fails() {
  home
  d=$(mktemp -d)
  printf 'API_SECRET=%s\n' "9f8e7d6c5b4a39281706f5e4d3c2b1a09f8e7d6c" > "$d/env.txt"
  expect_hit "$d" secret
}

# A JPEG with an EXIF GPS block. Built here so no media is committed.
make_gps_jpeg() {
  node -e '
    const t = Buffer.alloc(8 + 18 + 18);
    t.write("MM", 0); t.writeUInt16BE(42, 2); t.writeUInt32BE(8, 4);
    t.writeUInt16BE(1, 8); t.writeUInt16BE(0x8825, 10); t.writeUInt16BE(4, 12); t.writeUInt32BE(1, 14); t.writeUInt32BE(26, 18);
    t.writeUInt16BE(1, 26); t.writeUInt16BE(1, 28); t.writeUInt16BE(2, 30); t.writeUInt32BE(2, 32); t.write("N\0", 36, "latin1");
    const body = Buffer.concat([Buffer.from("Exif\0\0", "latin1"), t]);
    const app1 = Buffer.concat([Buffer.from([0xff, 0xe1]), Buffer.from([(body.length + 2) >> 8, (body.length + 2) & 255]), body]);
    require("fs").writeFileSync(process.argv[1], Buffer.concat([Buffer.from([0xff, 0xd8]), app1, Buffer.from([0xff, 0xd9])]));
  ' "$1"
}

test_gps_exif_jpeg_fails() {
  home
  d=$(mktemp -d); make_gps_jpeg "$d/photo.jpg"
  expect_hit "$d" media-gps
  out=$(scan "$d")
  case "$out" in *"photo.jpg:0: media-gps: "*) ;; *) echo "  $out"; exit 1;; esac
}

test_clean_jpeg_passes() {
  home
  d=$(mktemp -d)
  node -e 'require("fs").writeFileSync(process.argv[1], Buffer.from([0xff,0xd8,0xff,0xd9]))' "$d/plain.jpg"
  out=$(scan "$d") || { echo "  $out"; exit 1; }
  assert_eq "$out" "privacy ok" clean-jpeg
}

test_png_author_chunk_fails() {
  home
  d=$(mktemp -d)
  node -e '
    const crc = () => Buffer.alloc(4);
    const chunk = (t, b) => { const l = Buffer.alloc(4); l.writeUInt32BE(b.length); return Buffer.concat([l, Buffer.from(t, "latin1"), b, crc()]); };
    const png = Buffer.concat([Buffer.from([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]), chunk("tEXt", Buffer.from("Author\0Some Person", "latin1")), chunk("IEND", Buffer.alloc(0))]);
    require("fs").writeFileSync(process.argv[1], png);
  ' "$d/pic.png"
  expect_hit "$d" media-png-author
}

test_mp4_gps_box_fails() {
  home
  d=$(mktemp -d)
  node -e '
    const box = (t, b) => { const h = Buffer.alloc(8); h.writeUInt32BE(8 + b.length); h.write(t, 4, "latin1"); return Buffer.concat([h, b]); };
    const xyz = box("\xa9xyz", Buffer.from("+22.5726+088.3639/", "latin1"));
    const mp4 = Buffer.concat([box("ftyp", Buffer.from("isom0000", "latin1")), box("moov", box("udta", xyz))]);
    require("fs").writeFileSync(process.argv[1], mp4);
  ' "$d/clip.mp4"
  expect_hit "$d" media-mp4-gps
}

test_denylist_term_fails_and_is_masked() {
  home
  denylist_fixture "$HOME/deny.txt"
  d=$(mktemp -d); printf '%s\n' "$term" | tr '[:lower:]' '[:upper:]' > "$d/notes.md"
  out=$(KAITO_PRIVACY_DENYLIST="$HOME/deny.txt" node "$SCAN" "$d" 2>&1); rc=$?
  assert_eq "$rc" 1 exit
  case "$out" in *"$term"*) echo "  term printed"; exit 1;; esac
  case "$out" in *"notes.md:1: denylist: pri***"*) ;; *) echo "  expected a masked denylist match"; exit 1;; esac
}

test_denylist_matches_file_names_and_default_path() {
  home
  mkdir -p "$KAITO_HOME"; denylist_fixture "$KAITO_HOME/privacy-denylist.txt"
  d=$(mktemp -d); : > "$d/$term-deck.md"
  out=$(node "$SCAN" "$d" 2>&1); rc=$?
  assert_eq "$rc" 1 exit
  case "$out" in *"$term"*) echo "  file name printed"; exit 1;; esac
  case "$out" in *"pri***:0: denylist-path: pri***"*) ;; *) echo "  expected a masked denylist path"; exit 1;; esac
}

test_long_line_and_attribute_xmp_and_assignment_forms() {
  home
  d=$(mktemp -d)
  node -e 'require("fs").writeFileSync(process.argv[1], " ".repeat(30000) + " founder@" + "fixture.invalid\n")' "$d/min.json"
  expect_hit "$d" email
  d=$(mktemp -d); printf 'PHONE=%s%s\n' "98765" "43210" > "$d/e.env"
  expect_hit "$d" phone
  d=$(mktemp -d); printf 'API_TOKEN=%s\n' "123e4567-e89b-12d3-a456-426614174000" > "$d/e.env"
  expect_hit "$d" secret
}

test_truncated_media_does_not_crash() {
  home
  d=$(mktemp -d)
  node -e 'const fs=require("fs"),d=process.argv[1]; fs.writeFileSync(d+"/a.jpg",Buffer.from([0xff,0xd8,0xff,0xe1,0x00,0x30,0x45,0x78,0x69,0x66,0,0,0x4d,0x4d,0,0x2a,0,0,0,8,0,5])); fs.writeFileSync(d+"/b.mp4",Buffer.from([0,0,0,8,0x6d,0x6f,0x6f,0x76,0,0,0,8,0x6d,0x65,0x74,0x61])); fs.writeFileSync(d+"/c.png",Buffer.from([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a,0,0,0,50]));' "$d"
  printf 'x@%s\n' "fixture.invalid" > "$d/z.md"
  expect_hit "$d" email
}

test_quicktime_location_key_fails() {
  home
  d=$(mktemp -d)
  node -e '
    const box = (t, b) => { const h = Buffer.alloc(8); h.writeUInt32BE(8 + b.length); h.write(t, 4, "latin1"); return Buffer.concat([h, b]); };
    const keys = box("keys", Buffer.concat([Buffer.alloc(8), box("mdta", Buffer.from("com.apple.quicktime.location.ISO6709"))]));
    const mp4 = Buffer.concat([box("ftyp", Buffer.from("qt  0000")), box("moov", box("meta", keys))]);
    require("fs").writeFileSync(process.argv[1], mp4);
  ' "$d/clip.mov"
  expect_hit "$d" media-mp4-gps
}

test_xmp_attribute_form_fails() {
  home
  d=$(mktemp -d)
  node -e '
    const x = Buffer.from("http://ns.adobe.com/xap/1.0/\0<x:xmpmeta><rdf:Description tiff:Artist=\"Some Person\"/></x:xmpmeta>");
    const app1 = Buffer.concat([Buffer.from([0xff, 0xe1, (x.length + 2) >> 8, (x.length + 2) & 255]), x]);
    require("fs").writeFileSync(process.argv[1], Buffer.concat([Buffer.from([0xff, 0xd8]), app1, Buffer.from([0xff, 0xd9])]));
  ' "$d/x.jpg"
  expect_hit "$d" media-xmp-author
}

test_denylist_off_in_ci_mode() {
  home
  denylist_fixture "$HOME/deny.txt"
  d=$(mktemp -d); printf '%s\n' "$term" > "$d/notes.md"
  out=$(KAITO_PRIVACY_DENYLIST="$HOME/deny.txt" node "$SCAN" "$d" --no-denylist 2>&1) || { echo "  $out"; exit 1; }
  assert_eq "$out" "privacy ok" nodeny
}

test_fixture_owners_load() {
  for id in lumen-tea ira-das; do
    for f in owner.json brand.md voice.md icp.md offers.json channels.json; do assert_file "$OWNERS/$id/$f"; done
  done
  node -e '
    const fs = require("fs"), path = require("path");
    const root = process.argv[1];
    const need = { id: "string", name: "string", kind: "string", locale: "string", timezone: "string", currency: "string", bindings: "array", channels: "object", keys: "object", cloud_ok: "boolean" };
    for (const id of ["lumen-tea", "ira-das"]) {
      const o = JSON.parse(fs.readFileSync(path.join(root, id, "owner.json"), "utf8"));
      for (const [k, t] of Object.entries(need)) {
        const ok = t === "array" ? Array.isArray(o[k]) : t === "object" ? o[k] && typeof o[k] === "object" && !Array.isArray(o[k]) : typeof o[k] === t;
        if (!ok) { console.log(id + ": bad field " + k); process.exit(1); }
      }
      if (o.id !== id || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(o.id)) { console.log(id + ": id"); process.exit(1); }
      if (!["company", "person"].includes(o.kind)) { console.log(id + ": kind"); process.exit(1); }
      if (o.currency !== "INR" || o.timezone !== "Asia/Kolkata") { console.log(id + ": defaults"); process.exit(1); }
      if (!o.bindings.every((b) => path.isAbsolute(b))) { console.log(id + ": bindings must be absolute"); process.exit(1); }
      for (const f of ["offers.json", "channels.json"]) JSON.parse(fs.readFileSync(path.join(root, id, f), "utf8"));
      const offers = JSON.parse(fs.readFileSync(path.join(root, id, "offers.json"), "utf8"));
      if (offers.currency !== "INR" || !offers.offers.every((x) => Number.isInteger(x.price) && x.price > 0)) { console.log(id + ": offers"); process.exit(1); }
    }
    const a = JSON.parse(fs.readFileSync(path.join(root, "lumen-tea", "owner.json"), "utf8"));
    const b = JSON.parse(fs.readFileSync(path.join(root, "ira-das", "owner.json"), "utf8"));
    if (a.kind !== "company" || a.gstin !== "19ABCDE1234F1Z5" || b.kind !== "person" || "gstin" in b) { console.log("owner kinds or gstin"); process.exit(1); }
  ' "$OWNERS" || exit 1
}

# A second hit in the same file must not reveal a private path.
test_private_path_stays_masked_on_other_hits() {
  home
  denylist_fixture "$HOME/deny.txt"
  d=$(mktemp -d); printf 'contact x@%s\n' "fixture.invalid" > "$d/$term.md"
  out=$(KAITO_PRIVACY_DENYLIST="$HOME/deny.txt" node "$SCAN" "$d" 2>&1); rc=$?
  assert_eq "$rc" 1 exit
  case "$out" in *"$term"*) echo "  private path printed"; exit 1;; esac
}

test_oversized_file_fails_closed() {
  home
  d=$(mktemp -d)
  node -e 'require("fs").closeSync(require("fs").openSync(process.argv[1], "w")); require("fs").truncateSync(process.argv[1], 257 * 1024 * 1024)' "$d/large.txt"
  out=$(scan "$d"); rc=$?
  assert_eq "$rc" 2 exit
}
