#!/usr/bin/env bash
# Configure (the first time) and build word2pdf from a source tree inside the pinned build
# container. Later runs are incremental: only what changed is rebuilt and relinked.
#
#   scripts/build-linux.sh [SRC_DIR] [BUILD_DIR]
#
# SRC_DIR defaults to src/ (made by scripts/extract.sh), BUILD_DIR to work/build-linux-<arch>
# (or a named volume, see LO_SLIM_VOLUMES in scripts/lib.sh); the stripped binary goes to
# out/word2pdf-linux-<arch>, arch arm64 or x86_64 ($LO_SLIM_OUT instead of out/). Inside the
# container the sources are always /src and the build directory /build, so the executable does
# not depend on where they are on the host, and ccache shares compiled objects between build
# directories.
#
# Works with podman or docker; on Apple Silicon LO_SLIM_PLATFORM=linux/amd64 builds the x86-64
# binary.
# $LO_SLIM_CONFIGURE_ARGS adds configure options for a build directory.
# $LO_SLIM_MAKE_ARGS adds make variables, e.g. gb_COMPILEROPTFLAGS=-O2 (faster, bigger).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

build_image lo-slim-build "$ROOT/build"
ARCH="$(container_arch)"

SRC="$(absdir "${1:-$ROOT/src}")"
if [ -n "${2:-}" ]; then
    BUILD="$(absdir "$2")"
elif use_volumes; then
    BUILD="lo-slim-build-linux-$ARCH"
else
    BUILD="$(absdir "$ROOT/work/build-linux-$ARCH")"
fi
if [ -n "${LO_SLIM_CCACHE:-}" ]; then
    CCACHE="$(absdir "$LO_SLIM_CCACHE")"
elif use_volumes; then
    CCACHE=lo-slim-ccache
else
    CCACHE="$(absdir "$ROOT/work/ccache")"
fi
TARBALLS="$(absdir "${LO_SLIM_TARBALLS:-$ROOT/work/tarballs}")"
OUT="$(absdir "${LO_SLIM_OUT:-$ROOT/out}")"
BINARY="$(binary_name linux "$ARCH")"
echo "building $SRC in $BUILD for $ARCH"

container_run \
    -v "$SRC:/src" -v "$BUILD:/build" -v "$CCACHE:/ccache" -v "$TARBALLS:/tarballs" -v "$OUT:/out" \
    -v "$ROOT/scripts:/scripts:ro" \
    -e SOURCE_DATE_EPOCH=1767225600 -e BINARY="$BINARY" \
    -e LO_SLIM_CONFIGURE_ARGS="${LO_SLIM_CONFIGURE_ARGS:-}" \
    -e LO_SLIM_MAKE_ARGS="${LO_SLIM_MAKE_ARGS:-}" \
    -w /build lo-slim-build bash -euo pipefail -c '
        # the sources can belong to another user id inside the container (Docker Desktop)
        git config --global --add safe.directory "*"
        # the external library sources the tree needs (configure has --disable-fetch-external)
        python3 /scripts/fetch_tarballs.py /src /tarballs
        if [ ! -f config_host.mk ] || [ /src/distro-configs/LibreOfficeSlim.conf -nt config_host.mk ]; then
            /src/autogen.sh --with-distro=LibreOfficeSlim --with-external-tar=/tarballs $LO_SLIM_CONFIGURE_ARGS
        fi
        # only the slim module and what it depends on, not every target of every module
        make slim.allbuild $LO_SLIM_MAKE_ARGS
        strip -o "/out/$BINARY" instdir/program/word2pdf
    '
ls -l "$OUT/$BINARY"
