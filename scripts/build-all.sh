#!/usr/bin/env bash
# Build word2pdf natively for this Mac, then for Linux arm64 and x86-64 in the build container
# (x86-64 runs emulated and takes the longest). One build at a time: each already uses every
# core, and two container builds at once can exhaust the container VM's memory. A failed build
# does not stop the others; the exit status is non-zero if any failed.
#
#   scripts/build-all.sh
#
# The binaries go to out/macos-<arch>/, out/linux-aarch64/ and out/linux-x86_64/, each with a
# VERSION file, the output of each build to work/build-<target>.log. src/ is extracted first if
# it does not exist yet.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ "$(uname -s)" != Darwin ]; then
    echo "build-all.sh builds on macOS; use scripts/build-linux.sh elsewhere" >&2
    exit 1
fi
# checked now rather than after the macOS build
if ! "$ENGINE" info >/dev/null 2>&1; then
    echo "$ENGINE is not running" >&2
    exit 1
fi
# all three would write to the same file
unset LO_SLIM_OUT

[ -d "$ROOT/src/.git" ] || "$ROOT/scripts/extract.sh"
mkdir -p "$ROOT/work"

results=()
failed=0
build() {
    local target="$1" start=$SECONDS status=0
    shift
    echo "=== $target"
    "$@" 2>&1 | tee "$ROOT/work/build-$target.log" || status=$?
    local took="$(((SECONDS - start) / 60))m"
    if [ "$status" = 0 ]; then
        results+=("ok      $target  $took  out/$target/word2pdf  $(cat "$ROOT/out/$target/VERSION")")
    else
        results+=("FAILED  $target  $took  work/build-$target.log")
        failed=1
    fi
}

build "macos-$(uname -m)" "$ROOT/scripts/build-macos.sh"
build linux-aarch64 env LO_SLIM_PLATFORM=linux/arm64 "$ROOT/scripts/build-linux.sh"
build linux-x86_64 env LO_SLIM_PLATFORM=linux/amd64 "$ROOT/scripts/build-linux.sh"

echo
printf '%s\n' "${results[@]}"
exit $failed
