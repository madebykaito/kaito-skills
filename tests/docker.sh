#!/bin/sh
# Run the tests and the install smoke test in Linux containers (Debian, Alpine, Fedora).
# Usage: tests/docker.sh [debian|alpine|fedora]...   Needs Docker. Your checkout is mounted read-only.
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
[ $# -gt 0 ] || set -- debian alpine fedora
fail=0
for d in "$@"; do
  case "$d" in
    debian) img=node:22-bookworm prep='apt-get update -qq && apt-get install -y -qq python3 >/dev/null' ;;
    alpine) img=node:22-alpine prep='apk add --no-cache -q bash git curl python3 util-linux' ;;
    fedora) img=fedora:latest prep='dnf install -y -q nodejs npm git python3 util-linux which findutils diffutils >/dev/null' ;;
    *) echo "unknown distro: $d" >&2; exit 2 ;;
  esac
  echo "== $d ($img)"
  # Tests write temp files in the repo copy, so work on a copy, never the mounted checkout.
  if docker run --rm -v "$repo:/src:ro" "$img" sh -c "$prep && cp -R /src /w && cd /w &&
      git config --global --add safe.directory /w && tests/run.sh && tests/smoke.sh"; then
    echo "== $d ok"
  else
    echo "== $d FAILED"; fail=1
  fi
done
exit $fail
