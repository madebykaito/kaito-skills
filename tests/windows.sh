#!/bin/sh
# Run the tests, the install smoke test and the route check on Windows 11 (Git Bash), in a UTM VM on this Mac.
# Usage: tests/windows.sh            test the working tree, committed or not
#        tests/windows.sh --check    only boot the VM and check it is ready
# Build the VM once first: tests/windows/build.sh. Nothing is kept: the VM starts disposable,
# so every change made in it is thrown away when it stops, and the files this script makes are removed.
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
vm=${KAITO_WIN_VM:-kaito-windows-test}
port=${KAITO_WIN_PORT:-52222}
dir=${KAITO_HOME:-$HOME/.kaito}/vm
die() { echo "windows: $*" >&2; exit 1; }

command -v utmctl >/dev/null || die "UTM is not installed: brew install --cask utm"
st=$(utmctl status "$vm" 2>/dev/null) || die "no VM named $vm. Build it once: tests/windows/build.sh"
[ "$st" = stopped ] || die "VM $vm is $st. Stop it first: utmctl stop $vm"
[ -f "$dir/id_ed25519" ] || die "no SSH key in $dir. Rebuild the VM: tests/windows/build.sh"

ssh_() {
  ssh -i "$dir/id_ed25519" -p "$port" -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null kaito@127.0.0.1 "$@"
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/kaito-win.XXXXXX")
ref=refs/kaito/windows-test-$$
cleanup() {
  utmctl stop --kill "$vm" >/dev/null 2>&1 || true
  i=0; while [ "$(utmctl status "$vm" 2>/dev/null)" != stopped ] && [ $i -lt 30 ]; do sleep 1; i=$((i + 1)); done
  git -C "$repo" update-ref -d "$ref" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

utmctl start --hide --disposable "$vm"
t=$(date +%s)
until ssh_ true 2>/dev/null; do
  [ $(( $(date +%s) - t )) -lt 300 ] || die "no SSH from the VM after 5 minutes"
  sleep 3
done
echo "== windows: VM up in $(( $(date +%s) - t ))s"

if [ "${1:-}" = --check ]; then
  ready=$(ssh_ 'cat /c/kaito-ready; git --version; node --version' 2>&1) || die "VM not ready: $ready"
  echo "$ready"
  case "$ready" in ok*) echo "== windows: ready"; exit 0 ;; *) die "first boot did not finish: $ready" ;; esac
fi

# Snapshot the working tree (tracked, changed and new files) as a commit, without touching the index.
cp "$repo/.git/index" "$tmp/index"
GIT_INDEX_FILE=$tmp/index git -C "$repo" add -A
tree=$(GIT_INDEX_FILE=$tmp/index git -C "$repo" write-tree)
commit=$(git -C "$repo" -c user.name=test -c user.email=test@localhost commit-tree "$tree" -p HEAD -m 'windows test')
git -C "$repo" update-ref "$ref" "$commit"
git -C "$repo" bundle create -q "$tmp/repo.bundle" "$ref"

# Clone it the way a Windows user gets the repo (Git for Windows defaults), then run the checks.
ssh_ 'cat >/c/repo.bundle' <"$tmp/repo.bundle"
ssh_ "set -e
  rm -rf /c/w; git init -q /c/w; cd /c/w
  git fetch -q /c/repo.bundle '$ref'; git checkout -q FETCH_HEAD
  echo '== windows: tests/run.sh'; tests/run.sh
  echo '== windows: tests/smoke.sh'; tests/smoke.sh
  out=\$(helpmekaito/scripts/check-routes.sh); echo \"\$out\"; echo \"\$out\" | grep -qx 'routes ok'" &&
  { echo "== windows ok"; exit 0; }
echo "== windows FAILED"; exit 1
