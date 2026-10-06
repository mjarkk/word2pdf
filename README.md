# `word2pdf` (WIP)

**Word to PDF converter that works and no more**.

A heavily stripped-down LibreOffice that does exactly one thing: turn a Word document into a PDF. No UI, no spreadsheets or slides, no background processes, just Writer and the PDF export in a single executable, built to do that one job well.

```sh
word2pdf input.docx output.pdf
word2pdf - - < input.docx > output.pdf   # or stream it
```

- **Real LibreOffice output**: the same layout engine and PDF export, not an approximation.
- **One file**: no LibreOffice install, no config, no runtime files. Linux needs only glibc 2.38+.
- **Word's standard fonts covered**: same-width stand-ins for Calibri, Cambria, Arial, Times New Roman and Courier New are built in, so documents keep their layout without installing anything.
- **Fast**: 0.05–0.5 s per document, ~100 MB of memory.
- **Safe in parallel**: no shared profile, no lock files, no leftover processes.
- **Never hangs**: `--timeout` (default 120 s) stops a stuck conversion.
- **Leaves nothing behind**: scratch files are removed on success, failure, crash or SIGTERM. The PDF only appears once it is complete.
- **docx, doc, rtf and odt**: charts, formulas, SmartArt, tracked changes and every language, tested against 111 documents.
- **Linux** (x86-64, arm64) and **macOS** (Apple Silicon).

## Get it

Download `word2pdf` from the latest [release](https://github.com/mjarkk/word2pdf/releases), or [build it yourself](docs/DEVELOPMENT.md#building).

Recommended: install the other fonts and hyphenation dictionaries your documents use, so they look the same as in Word. On Ubuntu 24.04+:

```sh
apt-get install --no-install-recommends \
    fonts-dejavu fonts-noto-core fonts-noto-cjk fonts-droid-fallback \
    fonts-linuxlibertine fonts-sil-gentium-basic ttf-mscorefonts-installer \
    hyphen-en-us hyphen-nl hyphen-de hyphen-fr
word2pdf --update-font-cache   # once, e.g. in your Dockerfile; otherwise every run rescans the fonts
```

- `ttf-mscorefonts-installer`: the real Arial, Times New Roman, Courier New, Verdana and Georgia. Installing it downloads the fonts and asks you to accept Microsoft's EULA (preseed `msttcorefonts/accepted-mscorefonts-eula` for unattended installs).
- `fonts-noto-core`, `fonts-noto-cjk`: Arabic, Hebrew, Thai and other scripts; Chinese, Japanese and Korean.
- `hyphen-*`: automatic hyphenation, one package per document language.
- **macOS**: hyphenation dictionaries (`hyph_*.dic`) go in `/usr/local/share/hyphen` or `$DICPATH`.

If you ever have a layout issue it's most likely because you are missing one of the fonts listed below but most of these are proprietary and may not be free to redistribute:

| Font             | License                                                 |
| ---------------- | ------------------------------------------------------- |
| Calibri          | Proprietary (Microsoft), ships with Windows and Office  |
| Corbel           | Proprietary (Microsoft), ships with Windows and Office  |
| Century Gothic   | Proprietary (Monotype), ships with Office               |
| Helvetica        | Proprietary (Monotype), ships with macOS                |
| Helvetica Neue   | Proprietary (Monotype), ships with macOS                |
| Source Sans Pro  | SIL Open Font License 1.1 (Adobe), free to redistribute |
| Source Serif Pro | SIL Open Font License 1.1 (Adobe), free to redistribute |
