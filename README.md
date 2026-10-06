# `word2pdf` (WIP)

**Word to PDF converter that works and no more**.

A heavily stripped-down LibreOffice that does exactly one thing: turn a Word document into a PDF. No UI, no spreadsheets or slides, no background processes, just Writer and the PDF export in a single executable, built to do that one job well.

```sh
word2pdf input.docx output.pdf
word2pdf - - < input.docx > output.pdf   # or stream it
```

- **Real LibreOffice output**: the same layout engine and PDF export, not an approximation.
- **One file**: no LibreOffice install, no config, no runtime files. Linux needs only glibc 2.38+.
- **Fast**: 0.05–0.5 s per document, ~100 MB of memory.
- **Safe in parallel**: no shared profile, no lock files, no leftover processes.
- **Never hangs**: `--timeout` (default 120 s) stops a stuck conversion.
- **Leaves nothing behind**: scratch files are removed on success, failure, crash or SIGTERM. The PDF only appears once it is complete.
- **docx, doc, rtf and odt**: charts, formulas, SmartArt, tracked changes and every language, tested against 111 documents.
- **Linux** (x86-64, arm64) and **macOS** (Apple Silicon).

## Get it

Download `word2pdf` from the latest run of the [Build workflow](https://github.com/mjarkk/word-to-pdf-converter/actions/workflows/build.yml),
or [build it yourself](docs/DEVELOPMENT.md#building).

Recommended: install the fonts and hyphenation dictionaries your documents use, so they look the same as in Word. On Debian 13+ / Ubuntu 24.04+:

```sh
apt-get install --no-install-recommends \
    fonts-liberation fonts-crosextra-carlito fonts-crosextra-caladea fonts-dejavu \
    fonts-noto-core fonts-noto-cjk \
    hyphen-en-us hyphen-nl hyphen-de hyphen-fr
word2pdf --update-font-cache   # once, e.g. in your Dockerfile; otherwise every run rescans the fonts
```

- `fonts-liberation`, `-carlito`, `-caladea`: same-size stand-ins for Arial, Times New Roman, Courier New, Calibri and Cambria.
- `fonts-noto-core`, `fonts-noto-cjk`: Arabic, Hebrew, Thai and other scripts; Chinese, Japanese and Korean.
- `hyphen-*`: automatic hyphenation, one package per document language.
- **macOS**: `brew install --cask font-liberation font-carlito font-caladea`. Hyphenation dictionaries (`hyph_*.dic`) go in `/usr/local/share/hyphen` or `$DICPATH`.
