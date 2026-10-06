#!/usr/bin/env bash
# Convert testdata/corpus with the official LibreOffice build of the same version (LO_VERSION)
# into testdata/corpus-ref, with word2pdf's PDF options and its compiled-in fontconfig rules
# (testdata/fonts.conf, from slim/make_fonts_conf.py), so differences come from the build. Runs
# in the reference stage of build/test/Containerfile: the fonts scripts/test.sh has.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
tag=$(sed -n 's/^tag=//p' "$ROOT/LO_VERSION")
build_image lo-slim-ref "$ROOT/build/test" reference --build-arg "LO_VERSION=${tag#libreoffice-}"
rm -rf "$ROOT/testdata/corpus-ref"
mkdir -p "$ROOT/testdata/corpus-ref"

container_run -v "$ROOT/testdata:/testdata" \
    -e FILTER='pdf:writer_pdf_Export:{"UseTaggedPDF":{"type":"boolean","value":"false"},"ExportFormFields":{"type":"boolean","value":"false"}}' \
    lo-slim-ref bash -euo pipefail -c '
        FONTCONFIG_FILE=/testdata/fonts.conf soffice -env:UserInstallation=file:///tmp/profile \
            --headless --convert-to "$FILTER" --outdir /testdata/corpus-ref /testdata/corpus/* > /dev/null
    '
echo "$(ls "$ROOT/testdata/corpus-ref" | wc -l | tr -d ' ') reference PDFs in testdata/corpus-ref"
