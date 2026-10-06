#!/usr/bin/env bash
# Build word2pdf natively for this Mac, then for Linux x86-64 and arm64 in the build container
# (x86-64 runs emulated and takes the longest). One build at a time: each already uses every
# core, and two container builds at once can exhaust the container VM's memory. A failed build
# does not stop the others; the exit status is non-zero if any failed.
#
#   scripts/build-all.sh
#
# The binaries go to out/word2pdf-<os>-<arch> and the output of each build to
# work/build-<target>.log. Once all builds succeed, out/VERSION gets the version to release them
# as (see scripts/next-version.sh). src/ is extracted first if it does not exist yet.
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
VERSION="$("$ROOT/scripts/next-version.sh")"

[ -d "$ROOT/src/.git" ] || "$ROOT/scripts/extract.sh"
mkdir -p "$ROOT/work"
OUT="$(absdir "${LO_SLIM_OUT:-$ROOT/out}")"
rm -f "$OUT/VERSION"

results=()
failed=0
build() {
    local target="$1" start=$SECONDS status=0
    shift
    echo "=== $target"
    "$@" 2>&1 | tee "$ROOT/work/build-$target.log" || status=$?
    local took="$(((SECONDS - start) / 60))m"
    if [ "$status" = 0 ]; then
        results+=("ok      $target  $took  ${OUT#"$ROOT"/}/word2pdf-$target")
    else
        results+=("FAILED  $target  $took  work/build-$target.log")
        failed=1
    fi
}

build "macos-$(uname -m)" "$ROOT/scripts/build-macos.sh"
# arm64 last, so the build image ends up tagged for this Mac's platform
build linux-x86_64 env LO_SLIM_PLATFORM=linux/amd64 "$ROOT/scripts/build-linux.sh"
build linux-arm64 env LO_SLIM_PLATFORM=linux/arm64 "$ROOT/scripts/build-linux.sh"

echo
printf '%s\n' "${results[@]}"
if [ "$failed" = 0 ]; then
    echo "$VERSION" > "$OUT/VERSION"
    echo "${OUT#"$ROOT"/}/VERSION: $VERSION"
fi
exit $failed
