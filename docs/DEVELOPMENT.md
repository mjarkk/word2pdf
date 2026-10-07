# Development

How word2pdf is built, tested and put together. For using it, see the [README](../README.md).

`word2pdf`: LibreOffice's Writer and PDF export as **one static executable** that converts a
single document and exits, in place of `soffice --headless --convert-to pdf`: no
`oosplash`/`soffice.bin` pair, no IPC pipe, no user profile, no `gpg` children, nothing that
keeps running after the conversion.

```sh
word2pdf input.docx output.pdf          # files
word2pdf - - < input.docx > output.pdf  # stdin/stdout
word2pdf --help
```

| | `soffice --convert-to pdf` | `word2pdf` |
|---|---|---|
| processes | oosplash + soffice.bin (+ gpg, paperconf, ...) | one, no children |
| state on disk | user profile, lock files | private scratch dir, removed on exit/crash/SIGTERM |
| a hung conversion | stays around | `--timeout` (default 120 s) kills it, exit status 3 |
| runtime files | the LibreOffice installation | none: configuration, UNO registries, fontconfig rules and replacement fonts are compiled in; only installed fonts are read |
| shared libraries | ~200 | Linux: `libc`, `libm` (glibc ≥ 2.38); macOS: `libSystem`, `libc++`, CoreFoundation, Foundation |
| per conversion (test corpus) | | 0.05–0.2 s, peak RSS 90–110 MB |

Built from LibreOffice **26.2.6.3** (pinned in `LO_VERSION`).

## Results

`scripts/test.sh` converts `testdata/corpus` (108 documents from LibreOffice's own test suite:
docx, doc, rtf, odt, with charts, formulas, SmartArt, fields, tracked changes, ...; calibre's
demo document; a multilingual and a hyphenation document) in the test container and compares
with PDFs made by a regular LibreOffice 26.2.6.3 using the same fonts and font configuration
(`scripts/make-references.sh`), then checks that date fields use the document language
(`testdata/locale`). The Linux arm64 binary (`scripts/build-linux.sh` in Docker on Apple
Silicon) gives:

    converted 111/111, same pages 111, identical text 110, pixel-identical 99/111
    locale dates-nl.docx: ok
    locale dates-de.docx: ok

The references are made by LibreOffice on Linux, which turns a face name like "Calibri Light"
into fontconfig's generic fallback; word2pdf uses Carlito for it, as LibreOffice on Windows and
macOS does (patch 17), so two documents with Calibri Light headings are not pixel-identical.

The native macOS build (Apple Silicon) gives, with `scripts/test-macos.sh`, which points it at
the fonts and dictionaries of the test container so the same references apply:

    converted 111/111, same pages 110, identical text 109, pixel-identical 90/110
    locale dates-nl.docx: ok
    locale dates-de.docx: ok

96 of the 111 documents come out with identical results on both, the others differ by glyphs
placed about a pixel apart (also against references made by LibreOffice for aarch64), from
floating-point rounding; on macOS `sample-docx-files-sample1.docx` gets a ninth page. A
conversion takes 0.17 s (median; max 0.45 s), peak RSS 78 MB (median), and 0.2 s with the 2700
fonts of a stock Mac.

## How it works

The build is LibreOffice's own build system (gbuild) in its static mode, as used for the
WebAssembly and fuzzing builds:

* `--disable-dynamic-loading --enable-customtarget-components --disable-gui`
  (`overlay/distro-configs/LibreOfficeSlim.conf`): every library is a static archive and UNO
  components are found through a generated table of constructor functions instead of `dlopen`.
* `overlay/slim/` is a new module with the `word2pdf` executable:
  * [docs/LIBRARIES.md](LIBRARIES.md) lists every library in the executable, its size and
    its role; libraries that are referenced but never used for a conversion (password strength
    meter, online translation over curl, Markdown, OpenSSL) are kept out with stubs or
    configure options (`--disable-curl`, `--with-tls=no --disable-openssl`).
  * `components.txt` lists the UNO implementations to link (Writer and its import filters,
    charts, formulas, drawing, PDF export, ...). The linker then only pulls in code reachable
    from those, so Calc, Impress, Base, dialogs, spell checking etc. never end up in the
    binary. `update_constructors.py` expands it; `LO_SLIM_TRACE_IMPLEMENTATIONS=FILE` lists
    what a run instantiates.
  * `CustomTarget_assets.mk` compiles the runtime files (configuration `*.xcd`, UNO type and
    service registries, a few share/ files, the fontconfig configuration) into the executable;
    `LO_SLIM_TRACE_FILES=FILE` lists which ones a run looks for (not all are needed: Writer
    also opens `palette/standard.sob`, fill bitmaps for its dialogs).
  * Fonts are compiled in too (7.6 MB): the metric-compatible replacements LibreOffice
    bundles, Carlito, Caladea and Liberation Sans, Serif and Mono, for Calibri, Cambria, Arial,
    Times New Roman and Courier New; and LibreOffice's OpenSymbol, for symbol fonts that are not
    installed (Word's bullets are in Symbol) and formulas. Not Liberation Sans Narrow, which is
    GPL-licensed. They stay on macOS too, although it has Arial, Times New Roman and Courier
    New: documents made with LibreOffice use Liberation by name, and fontconfig would replace
    Liberation Sans with Verdana, which is wider. fontconfig and FreeType read fonts from files,
    so each run copies them into anonymous in-memory files (`memfd_create`; on macOS unlinked
    files in the scratch directory) and registers them by LibreOffice's `/:FD:/<descriptor>`
    names, which its FreeType, cairo and PDF font subsetting already understand. That takes
    about 10 ms per conversion.
  * `make_fonts_conf.py` ends the fontconfig configuration with a rule that removes the
    generic family from requests. fontconfig 2.17 ranks it above the requested family, and
    VCL adds "sans" or "serif" to every request, so any "... Sans" font won over an alias
    like Calibri → Carlito.
  * `assets/share/registry/word2pdf.xcd` holds the baked-in defaults: PDF settings
    (no tagged PDF, no form fields), no lock files, and a fixed locale (en-US), which
    also stops LibreOffice from running `paperconf` to guess the paper size.
  * `icu-data-remove.txt` drops ICU data LibreOffice does not use (display names of languages,
    regions, currencies, time zones and units; charset converters; transliteration rules, ICU's
    own line break rules, character names, StringPrep, the spoof checker and NFKC): 33 MB →
    11 MB.
  * All of LibreOffice's locale data is included (`--with-locales=ALL`): documents get the date
    and number formats, and the CJK line breaking, of their own language.
* `patches/` are the changes to LibreOffice itself:
  1. `sal`: a read-only file tree in memory (generalising the Android `/assets` support), so
     the embedded files are served through the normal file API.
  2. `cppuhelper`: static executables can name their `unorc`.
  3. gbuild: link only the libraries of the listed components.
  4. gbuild: allow source trees with modules left out.
  5. `svidl`: GCC-compatible weak type maps for static builds.
  6. bundled fontconfig as a static library.
  7. register the `slim` module.
  8. optionally build ICU with less data (and no dylib renaming in a static macOS build).
  9. skip duplicate script-tagged hyphenation dictionaries (Debian's `hyph_en_Latn_US.dic`),
     whose tag would make every run load liblangtag's database (+45 MB, +30 ms).
  10. compile for size (`-Os`) when building with the `slim` module.
  11. `i18nutil`: a program can set the default paper size.
  12. macOS: a static build without GUI, on the headless backend as on Linux: configure
      (`--disable-gui` with `--enable-headless`, no OpenGL), static libraries in gbuild's macOS
      platform, VCL and sfx2 without their Cocoa parts, the bundled libraries without dylib
      post-processing; sal no longer probes every possible file descriptor at startup (0.1 s
      with an open-file limit of 1048576).
  13. `vcl`: a cheaper check for duplicate fonts; with the 2700 fonts of a Mac it took 0.5 s of
      every conversion.
  14. `bridges`: the arm64 UNO bridge flushes the instruction cache without `dlsym`, which finds
      nothing in a static executable (every Linux arm64 conversion crashed).
  15. `autogen.sh`: recognises Git Bash on Windows ARM64 (`clangarm64` on the `PATH`) for the
      WSL-helper build, as configure already does.
  16. Windows (in progress, see [docs/PORTING.md](PORTING.md)): MSVC builds with static
      libraries instead of DLLs, and the bundled libraries built static.
  17. `vcl`: a font named after one weight of its family ("Calibri Light", "Segoe UI
      Semibold") that is not installed becomes that family, or its metric-compatible
      replacement (Carlito), in that weight. On Linux LibreOffice asked fontconfig first,
      which never knows these names and answers with its generic fallback; LibreOffice on
      Windows and macOS already got there.
  18. `comphelper`: without a TLS library (`--with-tls=no`), MD5 and SHA-1 come from sal's
      own implementation instead of being all zeros; the PDF writer makes the document ID with
      MD5. SHA-2 is left out: only decrypting documents, encrypting PDFs and password hashes
      use it, and word2pdf does none of these (it refuses passwords).
  19. `vcl`: no JSDialog builders, which make LibreOffice Online's dialogs; word2pdf never runs
      as LibreOfficeKit.
  20. `unoidl`: a static build reads only binary type registries, no `.idl` files or the legacy
      registry format (a static build is a cross build, whose build tools are linked
      dynamically).

## Building

Linux, inside a pinned Debian container (`build/Containerfile`, podman):

```sh
scripts/fetch.sh          # clone LibreOffice at the pinned tag into repos/core (once)
scripts/extract.sh        # src/: only the modules in modules.txt + patches + overlay
scripts/build-linux.sh    # configure and build src/ -> out/word2pdf-linux-x86_64
```

`src/` is a standalone source tree (~330 MB instead of ~1.8 GB, its own git repository with a
reproducible commit id): the LibreOffice modules word2pdf is linked from, as listed in
`modules.txt`, which was derived from the static link closure that gbuild computes for the
executable. `scripts/fetch_tarballs.py` downloads the 36 external library tarballs the tree
builds from LibreOffice's mirror, checked against the SHA-256 sums in `download.lst`; the build
itself does not download anything (`--disable-fetch-external`).

Size: the code is compiled with `-Os` (patch 0010; -21% size and -10% memory, ~20% slower:
+30 ms on a typical document; `LO_SLIM_MAKE_ARGS=gb_COMPILEROPTFLAGS=-O2` for speed) and
linked with mold, which folds identical functions (-6%) and relinks in seconds. Together with
leaving out unused libraries this made the executable about a quarter smaller. Link-time
optimisation does not help on top of that (`--enable-lto` makes it ~15% bigger with `-Os`).

The first build of a build directory takes ~25 minutes on 16 cores; after that builds are
incremental: changing one source file and relinking takes ~10 s.

On a Mac the container's build directory, compiler cache (ccache) and a copy of `src/` are
Docker volumes (`lo-slim-build-linux-<arch>`, `lo-slim-ccache`, `lo-slim-src`): through a bind
mount of the Mac's file system, reading the sources is 20–30 times slower, which ccache hits feel
most, since each one hashes every header the file includes. `build-linux.sh` first brings the
copy up to date with rsync (a few seconds), keeping modification times, so only what changed is
rebuilt. A change to a header nearly everything includes (`include/sal/types.h`) still
recompiles everything once per architecture; x86-64 runs under Rosetta at about half speed.

macOS, natively with Xcode and a few Homebrew tools (macOS's own make and gperf are too old):

```sh
brew install make gperf ninja cmake autoconf automake pkgconf
scripts/fetch.sh
scripts/extract.sh
scripts/build-macos.sh    # -> out/word2pdf-macos-arm64 (work/build-macos-arm64)
scripts/test-macos.sh     # corpus + locale checks; needs Docker or podman for the test
                          # fonts, and poppler and Pillow
```

It renders like the Linux build (VCL's headless backend with cairo, FreeType and the bundled
fontconfig) rather than through CoreText. `build-macos.sh` runs the build with only the system's
tools and the Homebrew tools it needs on the `PATH`, so nothing links against Homebrew's
libraries. Unlike the container build, the result is not independent of the directories it was
built in (some messages carry source paths).

On a Mac, `scripts/build-all.sh` builds all three binaries: first for macOS, then Linux x86-64
in the container (under emulation and so the slowest), then Linux arm64. Each binary goes to
`out/word2pdf-<os>-<arch>` and each log to `work/build-<target>.log`. A failed build does not stop
the others.

Once all three builds succeed, `build-all.sh` writes `out/VERSION`, the name to release them under:
`LibreOffice-<version>-B<n>`. `<version>` is the LibreOffice version in `LO_VERSION`. `<n>` starts
at 1 and is one more than the highest number ending an existing GitHub release tag for that
LibreOffice version (drafts included), so several word2pdf releases can be built on the same
LibreOffice. `scripts/next-version.sh` prints it on its own; both need the GitHub CLI (`gh`),
logged in.

Windows (ARM64 or x64), natively with Visual Studio 2022, set up the way LibreOffice's own
Windows builds are: autogen.sh and configure run in WSL, everything else natively from Git Bash.
The environment works; word2pdf itself is not ported yet, so configure stops at the first
Unix-only option (see [docs/PORTING.md](PORTING.md)).

```powershell
# elevated PowerShell, once: Visual Studio, Git, Python, WSL1 with Ubuntu, make, pkgconf and
# Strawberry Perl (in C:\lo-tools); asks for one reboot, then run it again
powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
```

```sh
# Git Bash; keep the checkout at a short path such as C:\word2pdf (Windows path length limits)
scripts/fetch.sh
scripts/extract.sh
scripts/build-windows.sh  # -> out/word2pdf-windows-arm64.exe (work/build-windows-aarch64)
```

Builds are reproducible: the same `src/` built in two different directories gives a
bit-for-bit identical executable (fixed in-container paths, `SOURCE_DATE_EPOCH`, and `src/` as a
single commit with fixed metadata, whose id LibreOffice embeds as its build id). Inside the container the
sources are always `/src` and the build directory `/build`, so the result does not depend on
host paths and ccache reuses objects between build directories.

Development loop:

```sh
# edit work/core (a git worktree of repos/core on the pinned tag), then:
scripts/export-patches.sh   # work/core changes -> overlay/ + patches/
scripts/extract.sh          # -> src/, only changed files are touched
scripts/build-linux.sh      # incremental
scripts/test.sh             # corpus + locale checks against the reference PDFs
```

After changing `overlay/slim/components.txt`, regenerate the constructor list from a build
(`overlay/slim/update_constructors.py BUILD_DIR/workdir`, then export/extract/build).

## Status and next steps

* Linux x86-64: works (see above). Linux arm64: works, built in Docker on Apple Silicon.
* macOS on Apple Silicon: works, built natively (see above). Intel Macs: `build-macos.sh` builds
  for the machine it runs on, but this has not been tried.
* Windows: the build environment works (`scripts/setup-windows.ps1`, tried on ARM64), the port
  is not done; see [docs/PORTING.md](PORTING.md) for the plan (configure, a Win32 embedded
  file tree, an MSVC static build and a headless backend). Meanwhile the Linux binary runs in
  Docker/WSL2.
* Older glibc: building in an older base image (or against musl) would lower the glibc ≥ 2.38
  requirement.

## License

word2pdf is distributed under the [Mozilla Public License 2.0](../LICENSE), like LibreOffice:

* `patches/` change LibreOffice's own files, which are MPL-2.0 (the ones LibreOffice inherited
  from OpenOffice.org also carry an Apache License 2.0 notice); `overlay/`, the scripts and the
  build files are this project's own.
* `testdata/` holds documents from elsewhere; [testdata/README.md](../testdata/README.md) says where
  each comes from.
* A word2pdf executable, and any image containing one, has to be distributed together with
  [THIRD-PARTY-NOTICES.txt](../THIRD-PARTY-NOTICES.txt): the license terms of LibreOffice and of
  every library linked in, and where the source code of all of it is. Where a library offers a
  choice, the notices name a license other than the GPL or LGPL: the GPL would extend to all of
  word2pdf, and a static executable can only meet the LGPL's relinking requirement by shipping
  its object files.

Regenerate the notices after changing `LO_VERSION`, `modules.txt`, `overlay/slim/components.txt`
or the configure options (CI fails when the license texts are out of date):

```sh
scripts/third_party_notices.py repos/core work/tarballs THIRD-PARTY-NOTICES.txt
```

The list of libraries in that script is maintained by hand: a library that newly ends up in the
executable has to be added to it.
