#!/usr/bin/env bash
# Configure (the first time) and build word2pdf natively on Windows, from Git Bash. Later runs are
# incremental: only what changed is rebuilt and relinked.
#
#   scripts/build-windows.sh [SRC_DIR] [BUILD_DIR]
#
# SRC_DIR defaults to src/ (made by scripts/extract.sh), BUILD_DIR to work/build-windows-<arch>;
# the executable goes to out/word2pdf-windows-<arch>.exe ($LO_SLIM_OUT instead of out/).
#
# Needs what scripts/setup-windows.ps1 installs. As in LibreOffice's own Windows builds, autogen.sh
# and configure run in WSL, and make and Visual Studio natively.
#   LO_SLIM_TOOLS           where setup-windows.ps1 put make, pkgconf and Strawberry Perl
#                           (default C:/lo-tools)
#   LO_SLIM_WSL_DISTRO      the WSL distribution configure runs in (default Ubuntu-24.04)
#   LO_SLIM_CONFIGURE_ARGS  adds configure options for a build directory
#   LO_SLIM_MAKE_ARGS       adds make variables
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case "$(uname -s)" in
    MINGW*|MSYS*) ;;
    *) echo "build-windows.sh runs in Git Bash on Windows" >&2; exit 1 ;;
esac

TOOLS="$(cygpath -u "${LO_SLIM_TOOLS:-C:/lo-tools}")"
DISTRO="${LO_SLIM_WSL_DISTRO:-Ubuntu-24.04}"
for tool in make.exe pkgconf-2.4.3.exe; do
    if [ ! -x "$TOOLS/bin/$tool" ]; then
        echo "missing $TOOLS/bin/$tool: run scripts/setup-windows.ps1" >&2
        exit 1
    fi
done
export PATH="$TOOLS/bin:$PATH"

# Git Bash itself is an x64 program, which sees PROCESSOR_ARCHITECTURE=AMD64 on ARM64 too
case "$(uname -s)" in
    *-ARM64) ARCH=aarch64 ;;
    *) ARCH=x86_64 ;;
esac
SRC="$(absdir "${1:-$ROOT/src}")"
BUILD="$(absdir "${2:-$ROOT/work/build-windows-$ARCH}")"
TARBALLS="$(absdir "${LO_SLIM_TARBALLS:-$ROOT/work/tarballs}")"
OUT="$(absdir "${LO_SLIM_OUT:-$ROOT/out}")"
BINARY="$(binary_name windows "$ARCH").exe"
echo "building $SRC in $BUILD for $ARCH"

wsl_path() {
    local p
    p="$(cygpath -m "$1")"
    printf '/mnt/%s%s\n' "$(printf %s "${p:0:1}" | tr '[:upper:]' '[:lower:]')" "${p:2}"
}

export SOURCE_DATE_EPOCH=1767225600
# the external library sources the tree needs (configure has --disable-fetch-external)
python "$ROOT/scripts/fetch_tarballs.py" "$SRC" "$TARBALLS"

cd "$BUILD"
if [ ! -f config_host.mk ] || [ "$SRC/distro-configs/LibreOfficeSlim.conf" -nt config_host.mk ] \
    || [ "$SRC/configure.ac" -nt config_host.mk ]; then
    # The build runs Python natively, so configure (in WSL) must not pick WSL's own; the short
    # path has no spaces, which configure's paths must not contain.
    python="$(cygpath -m -s "$(command -v python).exe")"
    windows="--host=$ARCH-pc-cygwin --with-visual-studio=2022 --with-strawberry-perl-portable=$(cygpath -m "$TOOLS/spp") PYTHON=$python"
    # The static build is a cross build: a second configure run sets up the build tools, a
    # dynamic build that must be configured for Windows the same way; skia and Python are only
    # needed there for products that have them.
    build_platform="$windows --enable-python=no --disable-skia"
    # --enable-gui: word2pdf renders with VCL's Windows backend (in headless mode), which is the
    # GUI one; configure knows no system dictionaries on Windows.
    # Git Bash would rewrite the WSL paths into Windows ones
    MSYS_NO_PATHCONV=1 wsl.exe -d "$DISTRO" --cd "$(wsl_path "$BUILD")" -- \
        "$(wsl_path "$SRC")/autogen.sh" --with-distro=LibreOfficeSlim $windows \
        --with-external-tar="$(cygpath -m "$TARBALLS")" \
        --with-wsl-command="wsl.exe -d $DISTRO" \
        --with-build-platform-configure-options="$build_platform" \
        --enable-gui --without-system-dicts \
        ${LO_SLIM_CONFIGURE_ARGS:-}
fi
# only the slim module and what it depends on, not every target of every module
make slim.allbuild ${LO_SLIM_MAKE_ARGS:-}
cp instdir/program/word2pdf.exe "$OUT/$BINARY"
ls -l "$OUT/$BINARY"
