#!/usr/bin/env bash
# Development helper: turn the changes in the work/core worktree into overlay/ (new files that
# are entirely ours) and patches/ (changes to LibreOffice's own files), which extract.sh applies.
#
#   scripts/export-patches.sh [WORKTREE]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WT="$(realpath "${1:-$ROOT/work/core}")"

# Files that only exist in this project.
OVERLAY=(
    slim
    distro-configs/LibreOfficeSlim.conf
)

# one patch per line: name, then the LibreOffice files it changes or adds
PATCHES='
0001-sal-embedded-read-only-file-tree include/osl/detail/embeddedfs.h sal/osl/unx/embeddedfs.hxx sal/osl/unx/embeddedfs.cxx sal/osl/unx/file.cxx sal/osl/unx/file_misc.cxx sal/osl/unx/uunxapi.cxx sal/rtl/bootstrap.cxx sal/Library_sal.mk sal/util/sal.map sal/osl/w32/embeddedfs.hxx sal/osl/w32/embeddedfs.cxx sal/osl/w32/file.cxx sal/osl/w32/file_dirvol.cxx
0002-cppuhelper-static-executables cppuhelper/source/paths.cxx cppuhelper/source/servicemanager.cxx
0003-gbuild-restricted-static-components solenv/gbuild/static.mk static/CustomTarget_components.mk
0004-gbuild-extracted-trees solenv/gbuild/Module.mk solenv/gbuild/Rdb.mk solenv/gbuild/LinkTarget.mk postprocess/Module_postprocess.mk
0005-svidl-weak-type-maps-with-gcc idl/source/objects/types.cxx
0006-externals-static-fontconfig-optional-curl external/fontconfig/ExternalProject_fontconfig.mk RepositoryExternal.mk
0007-register-slim-module Repository.mk RepositoryModule_host.mk
0008-icu-optional-data-filter external/icu/ExternalProject_icu.mk external/icu/UnpackedTarball_icu.mk external/icu/icu4c-data-ignore-deps.patch.1
0009-lingucomponent-skip-duplicate-script-dictionaries lingucomponent/source/lingutil/lingutil.cxx
0010-gbuild-optimize-for-size solenv/gbuild/platform/com_GCC_defs.mk
0011-i18nutil-default-paper-override include/i18nutil/paper.hxx i18nutil/source/utility/paper.cxx
0012-macos-static-headless configure.ac solenv/gbuild/platform/macosx.mk sal/osl/unx/salinit.cxx sfx2/Library_sfx.mk sfx2/source/appl/shutdownicon.cxx vcl/Library_vcl.mk vcl/Module_vcl.mk vcl/headless/svpinst.cxx external/cairo/ExternalProject_cairo.mk external/cairo/ExternalProject_pixman.mk external/liblangtag/ExternalProject_liblangtag.mk external/liblangtag/ExternalPackage_liblangtag.mk external/libxslt/ExternalProject_libxslt.mk external/redland/ExternalProject_rasqal.mk external/redland/ExternalProject_redland.mk external/redland/ExternalPackage_raptor.mk external/redland/ExternalPackage_rasqal.mk external/redland/ExternalPackage_redland.mk
0013-vcl-faster-font-deduplication vcl/unx/generic/fontmanager/fontconfig.cxx
0014-bridges-aarch64-static-cache-flush bridges/source/cpp_uno/gcc3_linux_aarch64/cpp2uno.cxx
0015-autogen-wsl-helper-arm64 autogen.sh
0016-windows-static-build include/sal/types.h solenv/gbuild/platform/com_MSC_class.mk solenv/gbuild/platform/com_MSC_defs.mk external/argon2/ExternalPackage_argon2.mk external/argon2/ExternalProject_argon2.mk external/lcms2/ExternalProject_lcms2.mk external/libxml2/ExternalProject_libxml2.mk external/openssl/ExternalPackage_openssl.mk external/openssl/ExternalProject_openssl.mk vcl/win/app/salshl.cxx vcl/Library_vclplug_win.mk RepositoryFixes.mk
0017-vcl-family-of-weight-names vcl/source/font/PhysicalFontCollection.cxx
0018-comphelper-hash-without-tls comphelper/source/misc/hash.cxx
0019-vcl-without-jsdialog-builders vcl/source/window/builder.cxx vcl/source/control/WeldedTabbedNotebookbar.cxx
0020-unoidl-static-binary-registries-only unoidl/source/unoidl.cxx
'

patch_paths() {
    echo "$PATCHES" | while read -r name paths; do
        if [ -n "$name" ]; then
            printf '%s\n' $paths
        fi
    done
}

cd "$WT"
git add -N "${OVERLAY[@]}" $(patch_paths)

# every changed path must belong to exactly one patch or the overlay
changed=$(git diff --name-only)
listed=$(patch_paths)
unlisted=$(comm -23 <(echo "$changed" | grep -v -e '^slim/' -e '^distro-configs/LibreOfficeSlim.conf$' | sort) <(echo "$listed" | sort))
if [ -n "$unlisted" ]; then
    echo "changed but not assigned to a patch:" >&2
    echo "$unlisted" >&2
    git reset -q
    exit 1
fi

rm -rf "$ROOT/overlay" "$ROOT"/patches/*.patch
mkdir -p "$ROOT/overlay" "$ROOT/patches"
for path in "${OVERLAY[@]}"; do
    mkdir -p "$ROOT/overlay/$(dirname "$path")"
    cp -a "$path" "$ROOT/overlay/$path"
done
echo "$PATCHES" | while read -r name paths; do
    if [ -n "$name" ]; then
        git diff --no-color -- $paths > "$ROOT/patches/$name.patch"
    fi
done
git reset -q

find "$ROOT/overlay" -name '__pycache__' -prune -exec rm -rf {} +
ls -1 "$ROOT/patches"
