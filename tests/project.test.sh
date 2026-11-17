#!/bin/sh
. "$(dirname "$0")/lib.sh"
PR="$REPO/helpmekaito/scripts/kaito-project.sh"

# repo <name>: a git repo with one commit and a package.json
repo() {
  P="$(mktemp -d)/$1"; mkdir -p "$P"; P=$(cd "$P" && pwd -P)
  git -C "$P" init -q
  printf '{"scripts":{"test":"node t.js","build":"tsc"}}\n' > "$P/package.json"
  git -C "$P" add -A; git -C "$P" -c user.name=t -c user.email=t@t commit -qm init
}
skill() {  # skill <dir> <folder> <name> <desc line>
  mkdir -p "$P/$1/$2"
  printf -- '---\nname: %s\ndescription: %s\n---\nbody\n' "$3" "$4" > "$P/$1/$2/SKILL.md"
}
fp() { sh "$PR" scan "$P" | sed -n 's/^fp=//p'; }

test_scan_manifests_scripts_instructions() {
  mk_home; repo app; echo "# rules" > "$P/AGENTS.md"; : > "$P/pnpm-lock.yaml"
  out=$(sh "$PR" scan "$P")
  echo "$out" | grep -qx "root=$P" || { echo "$out"; exit 1; }
  echo "$out" | grep -q '^head=[0-9a-f]\{40\}$' || exit 1
  echo "$out" | grep -qx 'manifest: package.json' || exit 1
  echo "$out" | grep -qx 'manifest: pnpm-lock.yaml' || exit 1
  echo "$out" | grep -qx 'script: test: node t.js' || exit 1
  echo "$out" | grep -qx 'script: build: tsc' || exit 1
  echo "$out" | grep -qx 'instructions: AGENTS.md' || exit 1
}

test_local_skills_both_dirs() {
  mk_home; repo app
  skill .claude/skills a1 alpha "Does alpha things"
  skill .agents/skills b1 beta "Does beta things"
  mkdir -p "$P/.claude/skills/nofm"; echo "no frontmatter" > "$P/.claude/skills/nofm/SKILL.md"
  mkdir -p "$P/.claude/skills/folded"
  printf -- '---\nname: folded\ndescription: >\n  first part\n  second part\n---\n' > "$P/.claude/skills/folded/SKILL.md"
  long=$(printf 'x%.0s' $(seq 1 200)); skill .claude/skills long long "$long"
  out=$(sh "$PR" scan "$P" | grep '^local_skill: ')
  tab=$(printf '\t')
  echo "$out" | grep -qx "local_skill: alpha${tab}.claude/skills/a1/SKILL.md${tab}Does alpha things" || { echo "$out"; exit 1; }
  echo "$out" | grep -qx "local_skill: beta${tab}.agents/skills/b1/SKILL.md${tab}Does beta things" || { echo "$out"; exit 1; }
  echo "$out" | grep -qx "local_skill: nofm${tab}.claude/skills/nofm/SKILL.md${tab}" || { echo "$out"; exit 1; }
  echo "$out" | grep -qx "local_skill: folded${tab}.claude/skills/folded/SKILL.md${tab}first part second part" || { echo "$out"; exit 1; }
  d=$(echo "$out" | grep '^local_skill: long' | cut -f3)
  assert_eq "${#d}" 120 "desc cut"
}

test_fp_stable_and_sees_uncommitted_skill() {
  mk_home; repo app
  a=$(fp); b=$(fp)
  assert_eq "$a" "$b" stable
  [ -n "$a" ] || exit 1
  skill .claude/skills new1 new1 "added but never committed"
  c=$(fp)
  [ "$c" != "$a" ] || { echo "fp ignored an uncommitted skill"; exit 1; }
  skill .claude/skills new1 new1 "edited"
  [ "$(fp)" != "$c" ] || { echo "fp ignored an edit"; exit 1; }
}

test_changed_new_same_changed() {
  mk_home; repo app; skill .claude/skills s1 s1 "one"
  assert_eq "$(sh "$PR" changed "$P")" new first
  sh "$PR" record "$P" || exit 1
  assert_eq "$(sh "$PR" changed "$P")" same recorded
  s=$(sh "$REPO/helpmekaito/scripts/kaito-codegraph.sh" slug "$P"); f="$KAITO_HOME/memory/projects/$s.md"
  grep -q '^brief_fp: ' "$f" || exit 1
  grep -qx 'local_skill: s1 .claude/skills/s1/SKILL.md one' "$f" || { cat "$f"; exit 1; }
  skill .claude/skills s1 s1 "two"
  assert_eq "$(sh "$PR" changed "$P")" changed edited
  skill .agents/skills s2 s2 "other"
  sh "$PR" record "$P"
  assert_eq "$(grep -c '^local_skill:' "$f")" 2 "skills replaced"
  assert_eq "$(grep -c '^brief_fp:' "$f")" 1 "fp replaced"
  assert_eq "$(sh "$PR" changed "$P")" same again
}

test_non_git_dir() {
  mk_home; P="$(mktemp -d)/plain"; mkdir -p "$P"; P=$(cd "$P" && pwd -P)
  printf 'all:\n\techo hi\n' > "$P/Makefile"; skill .claude/skills x x "plain skill"
  out=$(sh "$PR" scan "$P")
  echo "$out" | grep -qx 'head=none' || { echo "$out"; exit 1; }
  echo "$out" | grep -qx 'manifest: Makefile' || exit 1
  echo "$out" | grep -q '^local_skill: x' || exit 1
  assert_eq "$(cd "$P" && sh "$PR" changed)" new first
  (cd "$P" && sh "$PR" record) || exit 1
  assert_eq "$(cd "$P" && sh "$PR" changed)" same recorded
}

test_default_dir_is_git_toplevel() {
  mk_home; repo app; mkdir -p "$P/sub/deep"
  out=$(cd "$P/sub/deep" && sh "$PR" scan)
  echo "$out" | grep -qx "root=$P" || { echo "$out"; exit 1; }
}
