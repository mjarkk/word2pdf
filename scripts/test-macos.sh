#!/usr/bin/env bash
# Convert the test corpus with a native macOS word2pdf and compare with the reference PDFs, like
# scripts/test.sh does in its container. The references were made with the fonts and hyphenation
# dictionaries of the test container (build/test/Containerfile), so those are copied out once
# (work/test-env/, needs docker or podman) and word2pdf is pointed at them alone: the Mac's own
# fonts would change font fallback and so the layout.
# Exits non-zero when a document fails to convert or a locale check fails.
#
#   scripts/test-macos.sh [WORD2PDF]
#
# WORD2PDF defaults to out/macos-<arch>/word2pdf. Needs poppler and Pillow
# (brew install poppler; python3 -m pip install pillow). The PDFs and report.json end up in
# work/test-macos.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BIN="${1:-$ROOT/out/macos-$(uname -m)/word2pdf}"
BIN="$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")"
ENV="$ROOT/work/test-env"

if [ ! -d "$ENV/fonts" ] || [ ! -d "$ENV/hyphen" ]; then
    build_image lo-slim-test "$ROOT/build/test" test
    rm -rf "$ENV" && mkdir -p "$ENV"
    # -h: Debian links some font and dictionary files to other places
    container_run lo-slim-test tar -chf - -C /usr/share fonts hyphen | tar -xf - -C "$ENV"
fi

# word2pdf's compiled-in rules (testdata/fonts.conf) with only the container's fonts
awk -v fonts="$ENV/fonts" -v cache="$ENV/fontconfig-cache" '
    /<dir[ >]|<cachedir[ >]/ { next }
    { print }
    /^<fontconfig>/ { print "\t<dir>" fonts "</dir>"; print "\t<cachedir>" cache "</cachedir>" }
' "$ROOT/testdata/fonts.conf" > "$ENV/fonts.conf"
export FONTCONFIG_FILE="$ENV/fonts.conf" DICPATH="$ENV/hyphen"

rm -rf "$ROOT/work/test-macos"
OUT="$(absdir "$ROOT/work/test-macos")"
"$BIN" --update-font-cache
python3 "$ROOT/scripts/compare.py" "$BIN" "$ROOT/testdata/corpus" "$ROOT/testdata/corpus-ref" "$OUT" > /dev/null
status=0
python3 "$ROOT/scripts/summarize.py" "$OUT/report.json" || status=1

# Locale data: date fields must use the document language (DATE fields show the current date,
# so only the weekday names are checked).
check_locale() {
    if "$BIN" "$ROOT/testdata/locale/$1" - 2>/dev/null | pdftotext - - | grep -qE "$2"; then
        echo "locale $1: ok"
    else
        echo "locale $1: FAILED (no match for $2)"
        status=1
    fi
}
check_locale dates-nl.docx "maandag|dinsdag|woensdag|donderdag|vrijdag|zaterdag|zondag"
check_locale dates-de.docx "Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag"
exit $status
