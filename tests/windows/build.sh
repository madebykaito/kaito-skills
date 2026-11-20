#!/bin/sh
# Build the Windows 11 ARM test VM in UTM, once. tests/windows.sh then runs the tests in it.
# Usage: tests/windows/build.sh <windows-iso> <utm-guest-tools-iso> [--delete-isos]
#   Windows 11 ARM64 ISO: https://www.microsoft.com/software-download/windows11arm64
#   Guest tools ISO:      https://getutm.app/downloads/utm-guest-tools-latest.iso
# Needs UTM (brew install --cask utm). Runs unattended, about 10-15 minutes.
# Keeps only the VM disk; --delete-isos removes the two ISOs once the VM is ready.
set -eu
here="$(cd "$(dirname "$0")" && pwd -P)"
vm=${KAITO_WIN_VM:-kaito-windows-test}
port=${KAITO_WIN_PORT:-52222}
dir=${KAITO_HOME:-$HOME/.kaito}/vm
die() { echo "windows-build: $*" >&2; exit 1; }

[ $# -ge 2 ] || die "usage: tests/windows/build.sh <windows-iso> <utm-guest-tools-iso> [--delete-isos]"
win=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")
tools=$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")
del=no; [ "${3:-}" = --delete-isos ] && del=yes
[ -f "$win" ] || die "no Windows ISO at $win"
[ -f "$tools" ] || die "no guest tools ISO at $tools"
command -v utmctl >/dev/null || die "UTM is not installed: brew install --cask utm"
utmctl status "$vm" >/dev/null 2>&1 && die "VM $vm already exists. Delete it first: utmctl delete $vm"

mkdir -p "$dir"; chmod 700 "$dir"
[ -f "$dir/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C kaito-windows-test -f "$dir/id_ed25519"

# Answer disc: autounattend.xml (with a fresh password), first-boot script, SSH key and the guest tools
# installer. The guest tools disc is not attached itself: it has its own Autounattend.xml.
stage=$(mktemp -d "${TMPDIR:-/tmp}/kaito-win.XXXXXX")
trap 'rm -rf "$stage"' EXIT
pw=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
umask 077; printf 'KAITO_WIN_PASSWORD=%s\n' "$pw" >"$dir/windows.env"; umask 022
mkdir "$stage/disc"
sed "s/@PASSWORD@/$pw/g" "$here/autounattend.xml" >"$stage/disc/autounattend.xml"
cp "$here/firstboot.ps1" "$stage/disc/firstboot.ps1"
cp "$dir/id_ed25519.pub" "$stage/disc/authorized_keys"
mkdir "$stage/gt"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$stage/gt" "$tools"
cp "$stage"/gt/utm-guest-tools*.exe "$stage/disc/" || { hdiutil detach -quiet "$stage/gt"; die "no installer on the guest tools ISO"; }
hdiutil detach -quiet "$stage/gt"
answer=$dir/answer.iso; rm -f "$answer"
hdiutil makehybrid -quiet -iso -joliet -default-volume-name KAITOSETUP -o "$answer" "$stage/disc"

echo "creating VM $vm"
osascript - "$vm" "$win" "$answer" "$port" <<'OSA' >/dev/null
on run argv
  set {vmName, winIso, answerIso, hostPort} to argv
  tell application "UTM"
    make new virtual machine with properties {backend:qemu, configuration:{name:vmName, architecture:"aarch64", memory:8192, cpu cores:4, hypervisor:true, uefi:true, tpm:true, rtc local time:true, displays:{{hardware:"virtio-ramfb"}}, drives:{{removable:true, source:(POSIX file winIso)}, {removable:true, source:(POSIX file answerIso)}, {interface:NVMe, guest size:65536}}, network interfaces:{{mode:emulated, port forwards:{{protocol:TCP, host address:"127.0.0.1", host port:(hostPort as integer), guest port:22}}}}}}
  end tell
end run
OSA

echo "installing Windows (unattended, about 10-15 minutes)"
utmctl start --hide "$vm"
# The Windows disc waits for a key before it boots; press one for the first seconds only.
# Use "x": space or Enter would reach Setup's focused Cancel button once Setup is up.
i=0; while [ $i -lt 15 ]; do
  osascript -e "tell application \"UTM\" to input keystroke (virtual machine named \"$vm\") text \"x\"" >/dev/null 2>&1 || true
  sleep 1; i=$((i + 1))
done
# Keep the latest screen in $dir/build-screen.png, so a stall can be read without opening UTM.
start=$(date +%s)
while [ "$(utmctl status "$vm")" != stopped ]; do
  osascript -e "tell application \"UTM\" to capture screen (virtual machine named \"$vm\") to (POSIX file \"$dir/build-screen.png\")" >/dev/null 2>&1 || true
  [ $(( $(date +%s) - start )) -lt 7200 ] || { utmctl stop "$vm" || true; die "install did not finish in 2 hours; last screen: $dir/build-screen.png"; }
  sleep 30
done
rm -f "$dir/build-screen.png"

echo "detaching the install discs"
osascript - "$vm" <<'OSA' >/dev/null
on run argv
  tell application "UTM"
    set vm to virtual machine named (item 1 of argv)
    set cfg to configuration of vm
    set keep to {}
    repeat with d in drives of cfg
      if removable of d is false then set end of keep to contents of d
    end repeat
    set drives of cfg to keep
    update configuration of vm with cfg
  end tell
end run
OSA
rm -f "$answer"

echo "checking the VM"
"$here/../windows.sh" --check || die "the VM did not come up ready; the install log is C:\\kaito-firstboot.log in the VM"

if [ "$del" = yes ]; then rm -f "$win" "$tools"; echo "deleted the ISOs"; fi
echo "VM $vm ready ($(du -sh "$(osascript -e "tell application \"UTM\" to POSIX path of (file of virtual machine named \"$vm\" as alias)")" | cut -f1) on disk)"
