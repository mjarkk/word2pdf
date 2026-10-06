#!/usr/bin/env bash
# Convert the test corpus with a word2pdf binary and compare with the reference PDFs, inside the
# test container (build/test/Containerfile), which has the fonts the references were made with.
# Exits non-zero when a document fails to convert or a locale check fails.
#
#   scripts/test.sh [WORD2PDF]
#
# WORD2PDF defaults to out/word2pdf-linux-<arch> for the container's architecture. The PDFs and
# report.json end up in work/test.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
build_image lo-slim-test "$ROOT/build/test" test
BIN="${1:-$ROOT/out/$(binary_name linux "$(container_run lo-slim-test uname -m)")}"
BIN="$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")"
rm -rf "$ROOT/work/test"
OUT="$(absdir "$ROOT/work/test")"

container_run \
    -v "$BIN:/usr/local/bin/word2pdf:ro" -v "$ROOT/testdata:/testdata:ro" \
    -v "$ROOT/scripts:/scripts:ro" -v "$OUT:/out" \
    lo-slim-test bash -euo pipefail -c '
        word2pdf --update-font-cache
        python3 /scripts/compare.py /usr/local/bin/word2pdf /testdata/corpus /testdata/corpus-ref /out > /dev/null
        status=0
        python3 /scripts/summarize.py /out/report.json || status=1

        # Locale data: date fields must use the document language (DATE fields show the
        # current date, so only the weekday names are checked).
        check_locale() {
            if word2pdf "/testdata/locale/$1" - 2>/dev/null | pdftotext - - | grep -qE "$2"; then
                echo "locale $1: ok"
            else
                echo "locale $1: FAILED (no match for $2)"
                status=1
            fi
        }
        check_locale dates-nl.docx "maandag|dinsdag|woensdag|donderdag|vrijdag|zaterdag|zondag"
        check_locale dates-de.docx "Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag"
        exit $status
    '
