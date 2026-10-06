#!/usr/bin/env bash
# Configure (the first time) and build word2pdf natively on macOS. Later runs are incremental:
# only what changed is rebuilt and relinked.
#
#   scripts/build-macos.sh [SRC_DIR] [BUILD_DIR]
#
# SRC_DIR defaults to src/ (made by scripts/extract.sh), BUILD_DIR to work/build-macos-<arch>;
# the stripped binary goes to out/macos-<arch>/word2pdf (or $LO_SLIM_OUT), next to a VERSION file
# with the LibreOffice version it is built on.
#
# Needs Xcode and some Homebrew packages (macOS's make and gperf are too old):
#   brew install make gperf ninja cmake autoconf automake pkgconf
# $LO_SLIM_CONFIGURE_ARGS adds configure options for a build directory.
# $LO_SLIM_MAKE_ARGS adds make variables, e.g. gb_COMPILEROPTFLAGS=-O2 (faster, bigger).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ "$(uname -s)" != Darwin ]; then
    echo "build-macos.sh builds on macOS; use scripts/build-linux.sh elsewhere" >&2
    exit 1
fi

# The build sees only the system's tools and these: configure refuses to run with Homebrew's
# pkg-config on the PATH, and nothing may pick up Homebrew's libraries.
if ! command -v brew >/dev/null; then
    echo "needs Homebrew (https://brew.sh): brew install make gperf ninja cmake autoconf automake pkgconf" >&2
    exit 1
fi
TOOLS="$(absdir "$ROOT/work/macos-tools")"
rm -f "$TOOLS"/*
brew="$(brew --prefix)"
for tool in make gperf ninja cmake autoconf autoheader autom4te autoreconf aclocal automake ccache nasm; do
    path=$(PATH="$brew/opt/make/libexec/gnubin:$brew/bin" command -v "$tool" || true)
    case "$tool:$path" in
        ccache:|nasm:) ;;
        *:) echo "missing $tool: brew install make gperf ninja cmake autoconf automake pkgconf" >&2; exit 1 ;;
        *) ln -s "$path" "$TOOLS/$tool" ;;
    esac
done
# Bundled libraries find each other through PKG_CONFIG_PATH; with an empty default search path
# nothing else is found (and configure accepts this pkg-config).
if [ ! -x "$brew/bin/pkg-config" ]; then
    echo "missing pkg-config: brew install pkgconf" >&2
    exit 1
fi
printf '#!/bin/sh\nPKG_CONFIG_LIBDIR="${PKG_CONFIG_LIBDIR-}" exec %s "$@"\n' "$brew/bin/pkg-config" > "$TOOLS/pkg-config"
chmod +x "$TOOLS/pkg-config"
export PATH="$TOOLS:/usr/bin:/bin:/usr/sbin:/sbin"

ARCH="$(uname -m)"
SRC="$(absdir "${1:-$ROOT/src}")"
BUILD="$(absdir "${2:-$ROOT/work/build-macos-$ARCH}")"
TARBALLS="$(absdir "${LO_SLIM_TARBALLS:-$ROOT/work/tarballs}")"
OUT="$(absdir "${LO_SLIM_OUT:-$ROOT/out/macos-$ARCH}")"
echo "building $SRC in $BUILD for $ARCH"

export SOURCE_DATE_EPOCH=1767225600
# the external library sources the tree needs (configure has --disable-fetch-external)
python3 "$ROOT/scripts/fetch_tarballs.py" "$SRC" "$TARBALLS"

cd "$BUILD"
if [ ! -f config_host.mk ] || [ "$SRC/distro-configs/LibreOfficeSlim.conf" -nt config_host.mk ]; then
    # There are no system hyphenation dictionaries on macOS; this directory and DICPATH are
    # searched instead.
    "$SRC/autogen.sh" --with-distro=LibreOfficeSlim --with-external-tar="$TARBALLS" \
        --with-external-hyph-dir=/usr/local/share/hyphen ${LO_SLIM_CONFIGURE_ARGS:-}
fi
# only the slim module and what it depends on, not every target of every module
make slim.allbuild ${LO_SLIM_MAKE_ARGS:-}
strip -o "$OUT/word2pdf" instdir/*.app/Contents/MacOS/word2pdf
"$OUT/word2pdf" --version | sed 's/^word2pdf, //' > "$OUT/VERSION"
ls -l "$OUT/word2pdf"
cat "$OUT/VERSION"
