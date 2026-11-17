#!/bin/sh
# Mirror one memory note to the Obsidian Local REST API. Never fails the caller.
set +x  # never trace: the key is read below
skip() { echo "obsidian mirror skipped: $*"; exit 0; }
[ "${1:-}" = push ] && [ -n "${2:-}" ] || skip "usage: push <note>"
note=$2
K="${KAITO_HOME:-$HOME/.kaito}"
here=$(cd "$(dirname "$0")" && pwd -P)
cfg() { node "$here/kaito-json.mjs" get "$K/config.json" "obsidian.$1" | tr -d '"'; }
[ "$(cfg enabled)" = true ] || skip disabled
url=$(cfg api_url); vault=$(cfg vault_path)
[ -n "$url" ] || skip "no api_url"
key=$(sed -n 's/^OBSIDIAN_API_KEY=//p' "$K/.env" 2>/dev/null | head -n1)
[ -n "$key" ] || skip "no api key"
# Notes come from the resolved memory folder. ponytail: a vault_root that does not exist is compared as written.
M=$(sh "$here/kaito-mem.sh" dir 2>/dev/null) || skip "no memory folder"
vr=$(cfg vault_root)
case "$vr" in "~") vr=$HOME ;; "~/"*) vr="$HOME/${vr#"~/"}" ;; esac
if [ -n "$vr" ]; then
  vr=$(cd "$vr" 2>/dev/null && pwd -P || printf %s "${vr%/}")
  mp=$(cd "$M" 2>/dev/null && pwd -P || printf %s "${M%/}")
  case "$mp/" in "$vr/"*) skip "memory is inside the vault" ;; esac  # Obsidian already sees these files
fi
case "$note" in
  *..*) skip "unknown note $note" ;;  # no path may leave the memory folder
  MEMORY.md) dest=Memory.md ;;
  global.md) dest=Global.md ;;
  projects/*.md) dest=$note ;;
  managers/*/*) skip "unknown note $note" ;;
  managers/*.md) dest=$note ;;
  tasks/*/*/*) skip "unknown note $note" ;;
  tasks/*/index.md) dest=$note ;;
  *) skip "unknown note $note" ;;
esac
[ -f "$M/$note" ] || skip "missing file $note"
dest=$(node -e 'console.log(process.argv[1].split("/").map(encodeURIComponent).join("/"))' "$vault/$dest")
# key goes via stdin config so it never appears in argv or output
code=$(printf 'header = "Authorization: Bearer %s"\n' "$key" | curl -sS --max-time 5 -K - -o /dev/null -w '%{http_code}' \
  -X PUT -H 'Content-Type: text/markdown' --data-binary "@$M/$note" "$url/vault/$dest" 2>/dev/null) \
  || skip "api unreachable"
case "$code" in 2??) ;; *) skip "http $code" ;; esac
