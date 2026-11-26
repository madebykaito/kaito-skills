#!/bin/sh
. "$(dirname "$0")/lib.sh"
OW="$REPO/business/scripts/kaito-owner.mjs"
MEM="$REPO/helpmekaito/scripts/kaito-mem.sh"

# ko <args>: sets out, err, rc
ko() { out=$(node "$OW" "$@" 2> "$HOME/err"); rc=$?; err=$(cat "$HOME/err"); }
dir() { d="$(mktemp -d)/$1"; mkdir -p "$d"; d=$(cd "$d" && pwd -P); }
lumen() { node "$OW" add lumen-tea --name "Lumen Tea Co." --kind company --gstin 19ABCDE1234F1Z5 > /dev/null || exit 1; }
ira() { node "$OW" add ira-das --name "Ira Das" --kind person > /dev/null || exit 1; }
has() { printf '%s\n' "$1" | grep -qx -- "$2" || { echo "  missing line: $2"; printf '%s\n' "$1" | sed 's/^/    /'; exit 1; }; }

test_no_owner_exits_4() {
  mk_home
  ko resolve; assert_eq "$rc" 4 rc; assert_eq "$out" none out
  ko list; assert_eq "$out" none list
}

test_one_owner_auto_resolves() {
  mk_home; lumen; dir anywhere
  ko resolve --cwd "$d"; assert_eq "$rc" 0 rc
  has "$out" "owner=lumen-tea"; has "$out" "root=$KAITO_HOME/owners/lumen-tea"
  has "$out" "memory=$KAITO_HOME/owners/lumen-tea/memory"; has "$out" "via=only"
  f="$KAITO_HOME/owners/lumen-tea/owner.json"
  [ "$(node -e 'const o=require(process.argv[1]);console.log(o.kind,o.currency,o.timezone,o.locale,o.gstin,o.cloud_ok)' "$f")" = "company INR Asia/Kolkata en-IN 19ABCDE1234F1Z5 false" ] || { cat "$f"; exit 1; }
  assert_file "$KAITO_HOME/owners/lumen-tea/memory"
}

test_two_owners_stop_without_a_name() {
  mk_home; lumen; ira; dir elsewhere
  ko resolve --cwd "$d"; assert_eq "$rc" 3 rc
  assert_eq "$(printf '%s\n' "$out" | head -n 1)" "ambiguous: ira-das lumen-tea" both
  ko resolve --owner ira-das --cwd "$d"; assert_eq "$rc" 0 named; has "$out" "owner=ira-das"; has "$out" "via=named"
  ko resolve --owner nobody; assert_eq "$rc" 4 unknown
  ko show --cwd "$d"; assert_eq "$rc" 3 show
}

test_binding_picks_one() {
  mk_home; lumen; ira; dir shop; mkdir -p "$d/reels/june"
  ko bind lumen-tea "$d"; assert_eq "$rc" 0 bind
  ko resolve --cwd "$d/reels/june"; assert_eq "$rc" 0 rc; has "$out" "owner=lumen-tea"; has "$out" "via=binding $d"
  ko bind lumen-tea "$d"; assert_eq "$out" "already bound: lumen-tea $d" again
  ko bind ira-das "$d"; assert_eq "$rc" 1 taken
  ko unbind "$d"; assert_eq "$rc" 0 unbind
  ko resolve --cwd "$d"; assert_eq "$rc" 3 after-unbind
  ko unbind "$d"; assert_eq "$rc" 4 unbind-again
  ko bind lumen-tea "$d/missing"; assert_eq "$rc" 4 missing-dir
}

test_nested_bindings_deepest_wins() {
  mk_home; lumen; ira; dir studio; mkdir -p "$d/clients/ira/art" "$d/tea"
  node "$OW" bind lumen-tea "$d" > /dev/null && node "$OW" bind ira-das "$d/clients/ira" > /dev/null || exit 1
  ko resolve --cwd "$d/clients/ira/art"; has "$out" "owner=ira-das"
  ko resolve --cwd "$d/tea"; has "$out" "owner=lumen-tea"
  ko resolve --cwd "$d/clients"; has "$out" "owner=lumen-tea"
  # two owners bound at the same depth around one folder: ambiguous, only those two named
  node "$OW" add third-co --name "Third Co" --kind company > /dev/null || exit 1
  f="$KAITO_HOME/owners/third-co/owner.json"
  node -e 'const fs=require("fs");const o=JSON.parse(fs.readFileSync(process.argv[1]));o.bindings=[process.argv[2]];fs.writeFileSync(process.argv[1],JSON.stringify(o))' "$f" "$d/clients/ira"
  ko resolve --cwd "$d/clients/ira/art"; assert_eq "$rc" 3 tie
  assert_eq "$(printf '%s\n' "$out" | head -n 1)" "ambiguous: ira-das third-co" tie-names
}

test_path_traversal_refused() {
  mk_home; lumen
  for id in ../lumen-tea ../../etc lumen-tea/.. Lumen-Tea lumen_tea -lumen lumen--tea ""; do
    ko resolve --owner "$id"; [ "$rc" = 2 ] || [ "$id" = "" ] || { echo "  $id: rc $rc"; exit 1; }
    ko add "$id" --name x --kind company; [ "$rc" = 2 ] || { echo "  add $id: rc $rc"; exit 1; }
  done
  ko show ../lumen-tea; assert_eq "$rc" 2 show
  (cd "$HOME" && sh "$MEM" where --owner ../lumen-tea > /dev/null 2>&1); assert_eq "$?" 2 mem
  assert_no "$KAITO_HOME/etc"
  # an owner folder whose record names another id is refused
  mkdir -p "$KAITO_HOME/owners/evil"; printf '{"id":"lumen-tea","name":"x","kind":"company"}' > "$KAITO_HOME/owners/evil/owner.json"
  ko list; assert_eq "$rc" 1 mismatch
  case "$err" in *'does not match its folder'*) ;; *) echo "$err"; exit 1 ;; esac
}

test_owner_json_validation() {
  mk_home
  ko add lumen-tea --name "Lumen" --kind shop; assert_eq "$rc" 1 kind
  case "$err" in *'kind must be company or person'*) ;; *) echo "$err"; exit 1 ;; esac
  ko add lumen-tea --name "Lumen" --kind company --currency rupees; assert_eq "$rc" 1 currency
  ko add lumen-tea --name "Lumen" --kind company --timezone Mars/Base; assert_eq "$rc" 1 tz
  ko add lumen-tea --name "Lumen" --kind company --gstin 123; assert_eq "$rc" 1 gstin
  ko add lumen-tea --kind company; assert_eq "$rc" 2 no-name
  assert_no "$KAITO_HOME/owners/lumen-tea"
  lumen; ko add lumen-tea --name x --kind company; assert_eq "$rc" 1 exists
  f="$KAITO_HOME/owners/lumen-tea/owner.json"
  edit() { node -e 'const fs=require("fs");const o=JSON.parse(fs.readFileSync(process.argv[1]));Object.assign(o,JSON.parse(process.argv[2]));fs.writeFileSync(process.argv[1],JSON.stringify(o))' "$f" "$1"; }
  cp "$f" "$HOME/good.json"
  edit '{"keys":{"instagram":"EAAG-not-a-path"}}'; ko resolve; assert_eq "$rc" 1 key-value
  case "$err" in *'keys.instagram must be the path of a key file'*) ;; *) echo "$err"; exit 1 ;; esac
  cp "$HOME/good.json" "$f"; edit '{"cloud_ok":"yes"}'; ko resolve; assert_eq "$rc" 1 cloud
  cp "$HOME/good.json" "$f"; edit '{"bindings":["relative/dir"]}'; ko resolve; assert_eq "$rc" 1 binding
  cp "$HOME/good.json" "$f"; edit '{"surprise":1}'; ko resolve; assert_eq "$rc" 1 unknown
  cp "$HOME/good.json" "$f"; printf '{not json' > "$f"; ko resolve; assert_eq "$rc" 1 json
  cp "$HOME/good.json" "$f"; edit '{"channels":{"instagram":"@lumentea.example"},"keys":{"instagram":"~/.config/meta/lumen-tea.env"}}'
  ko resolve; assert_eq "$rc" 0 good
}

test_shared_memory_root_refused() {
  mk_home; lumen; ira
  f="$KAITO_HOME/owners/ira-das/owner.json"
  node -e 'const fs=require("fs");const o=JSON.parse(fs.readFileSync(process.argv[1]));o.memory_root=process.argv[2];fs.writeFileSync(process.argv[1],JSON.stringify(o))' "$f" "$KAITO_HOME/owners/lumen-tea"
  ko resolve --owner ira-das; assert_eq "$rc" 1 rc
  case "$err" in *'share a memory folder'*) ;; *) echo "$err"; exit 1 ;; esac
}

test_wrong_owner_facts_never_load() {
  mk_home; lumen; ira; dir app; git -C "$d" init -q
  printf '%s\n' "- Lumen Tea ships first-flush Darjeeling" "rule: Lumen Tea posts in Bengali and English" > "$KAITO_HOME/owners/lumen-tea/memory/owner.md"
  printf '%s\n' "- Ira Das takes illustration commissions" "rule: Ira Das signs every post" > "$KAITO_HOME/owners/ira-das/memory/owner.md"
  (cd "$d" && sh "$MEM" note project "repo fact") || exit 1
  out=$(cd "$d" && sh "$MEM" where task --owner ira-das) || exit 1
  has "$out" "owner=ira-das"; has "$out" "owner_file=$KAITO_HOME/owners/ira-das/memory/owner.md"
  has "$out" "rule: Ira Das signs every post"; has "$out" "- Ira Das takes illustration commissions"
  printf '%s\n' "$out" | grep -q 'repo fact' || { echo "  project memory missing"; exit 1; }
  printf '%s\n' "$out" | grep -qi 'lumen' && { echo "  lumen-tea leaked:"; printf '%s\n' "$out"; exit 1; }
  # without --owner no owner memory loads at all
  out=$(cd "$d" && sh "$MEM" where) || exit 1
  printf '%s\n' "$out" | grep -qiE 'lumen|ira das|^owner' && { echo "  owner memory without --owner:"; printf '%s\n' "$out"; exit 1; }
  # memory_root moves one owner's memory elsewhere, and only that folder is read
  mkdir -p "$HOME/vault/ira"; echo "- Ira vault fact" > "$HOME/vault/ira/owner.md"
  f="$KAITO_HOME/owners/ira-das/owner.json"
  node -e 'const fs=require("fs");const o=JSON.parse(fs.readFileSync(process.argv[1]));o.memory_root="~/vault/ira";fs.writeFileSync(process.argv[1],JSON.stringify(o))' "$f"
  out=$(cd "$d" && sh "$MEM" where --owner ira-das) || exit 1
  has "$out" "- Ira vault fact"; has "$out" "owner_file=$HOME/vault/ira/owner.md"
  printf '%s\n' "$out" | grep -q 'illustration commissions' && { echo "  old folder read"; exit 1; }
  (cd "$d" && sh "$MEM" where --owner nobody > /dev/null 2>&1); assert_eq "$?" 4 unknown
  return 0
}

test_owner_capture_lands_in_owner_memory() {
  mk_home; lumen; ira; dir app; git -C "$d" init -q
  lf="$KAITO_HOME/owners/lumen-tea/memory/owner.md"; jf="$KAITO_HOME/owners/ira-das/memory/owner.md"
  r=$(cd "$d" && echo "Lumen Tea captions lead with the estate name" | KAITO_TODAY=2026-11-26 sh "$MEM" capture convention --owner lumen-tea) || exit 1
  assert_eq "$r" saved saved
  grep -qx 'learn: convention 1 2026-11-26 Lumen Tea captions lead with the estate name' "$lf" || { cat "$lf"; exit 1; }
  r=$(cd "$d" && echo "Lumen Tea captions lead with the estate name" | sh "$MEM" capture convention --owner lumen-tea) || exit 1
  assert_eq "$r" already_present again
  assert_no "$jf"
  ! grep -rq 'estate name' "$KAITO_HOME/memory/projects" 2>/dev/null || { echo "  landed in project memory"; exit 1; }
  ! grep -q 'estate name' "$KAITO_HOME/memory/global.md" 2>/dev/null || { echo "  landed in global"; exit 1; }
  grep -q ' owner:lumen-tea convention$' "$KAITO_HOME/memory/learning.log" || exit 1
  # global is refused with --owner; note owner and learn go to the owner file too
  (cd "$d" && echo "x y z" | sh "$MEM" capture preference global --owner lumen-tea > /dev/null 2>&1); assert_eq "$?" 2 global
  (cd "$d" && sh "$MEM" note owner "Ira Das invoices in INR" --owner ira-das) || exit 1
  (cd "$d" && sh "$MEM" learn preference "Ira Das prefers square crops" --owner ira-das) || exit 1
  grep -q 'Ira Das invoices in INR' "$jf" && grep -q '^learn: preference 1 .* Ira Das prefers square crops' "$jf" || { cat "$jf"; exit 1; }
  (cd "$d" && sh "$MEM" note owner "no owner named" > /dev/null 2>&1); assert_eq "$?" 2 note-no-owner
  # a learning recalls only for its owner, and forget with --owner removes it from that owner's file
  out=$(cd "$d" && sh "$MEM" where --owner lumen-tea); has "$out" "learn: convention 1 2026-11-26 Lumen Tea captions lead with the estate name"
  printf '%s\n' "$out" | grep -q 'square crops' && exit 1
  (cd "$d" && sh "$MEM" forget "Ira Das prefers square crops" owner --owner ira-das) || exit 1
  ! grep -q 'square crops' "$jf" || exit 1
  (cd "$d" && echo "key sk-abcdefghijklmnopqrstuv" | sh "$MEM" capture worked --owner lumen-tea > /dev/null 2>&1); assert_eq "$?" 2 secret
  return 0
}

test_repo_memory_unchanged_without_business() {
  mk_home; dir app; git -C "$d" init -q
  # a copy of helpmekaito/scripts with no business skill beside it
  s="$(mktemp -d)/helpmekaito/scripts"; mkdir -p "$s"; cp "$REPO"/helpmekaito/scripts/*.sh "$REPO"/helpmekaito/scripts/*.mjs "$s/"
  r=$(cd "$d" && echo "Repo lesson stays in the repo" | sh "$s/kaito-mem.sh" capture convention) || exit 1
  assert_eq "$r" saved saved
  (cd "$d" && sh "$s/kaito-mem.sh" where) | grep -q 'Repo lesson stays in the repo' || exit 1
  (cd "$d" && sh "$s/kaito-mem.sh" where --owner lumen-tea > /dev/null 2>&1); assert_eq "$?" 2 no-business
}
