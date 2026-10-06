# What is inside word2pdf

Every library linked into the executable, with what it contributes to the binary and what it
does when converting a Word document to PDF. Sizes come from a linker map of the 136 MB `-O2`
build (code + data actually pulled in, not the size of the library); the current build is
compiled with `-Os` and linked with identical code folding, which shrinks everything by roughly
a quarter.

## Writer and the Word import filters — 31 MB

| library | MB | role |
|---|---:|---|
| sw | 16.2 | Writer itself: the document model, the layout engine (pages, paragraphs, tables, sections, footnotes, frames), fields and numbering, and painting the laid-out pages, which is what the PDF export records |
| xo (xmloff) | 5.9 | ODF XML import/export: reads .odt input, and is used internally to copy charts and formulas embedded in documents |
| oox | 4.0 | Office Open XML: DrawingML shapes, pictures, themes, charts, SmartArt fallbacks, VML, document properties of .docx |
| sw_writerfilter | 2.8 | the .docx and .rtf import (turns WordprocessingML into a Writer document) |
| msword | 1.7 | the Word 97–2003 .doc import (and the export code that lives with it) |
| msfilter | 0.5 | helpers shared by the MS filters: escher/VML shapes, OLE, RTF utilities |
| swd | 0.0 | detects whether a file is a Writer format |

## Charts, formulas, embedded objects — 6 MB

| library | MB | role |
|---|---:|---|
| chart2 | 3.9 | chart model and renderer for charts embedded in documents |
| sm (starmath) | 1.2 | lays out formulas (Word's OMML equations, MathType objects) |
| embobj, emboleobj | 0.6 | embedded objects: charts/formulas as sub-documents, OLE objects with their preview images |

## Drawing and graphics — 13 MB

| library | MB | role |
|---|---:|---|
| svxcore, svx | 8.9 | the drawing layer: shapes, text boxes, images, custom (preset) shapes, groups, form controls |
| editeng | 1.8 | text engine for text inside shapes, text boxes, chart labels and comments |
| drawinglayer, drawinglayercore | 1.2 | turns shapes and graphics into primitives and paints them (into the PDF) |
| basegfx | 0.4 | geometry: polygons, curves, transformations, gradients |
| svgio | 0.3 | SVG pictures |
| emfio | 0.1 | EMF/WMF pictures (very common in Word documents) |
| docmodel | 0.0 | document themes (theme colours and fonts of .docx) |

## Output: VCL and the PDF writer — 9 MB

| library | MB | role |
|---|---:|---|
| vcl | 9.1 | the output layer: fonts and text layout, the PDF writer itself, decoding of PNG/JPEG/GIF/BMP/TIFF/WebP images, the headless backend |
| pdffilter | 0.1 | the writer_pdf_Export filter: PDF options, renders each page into vcl's PDF writer |

## Fonts and text rendering — 4 MB

| library | MB | role |
|---|---:|---|
| harfbuzz, graphite | 1.6 | text shaping: kerning, ligatures, Arabic/Indic/… scripts |
| cairo, pixman | 1.8 | raster backend of headless VCL (bitmaps, some effects) |
| freetype | 0.6 | reads font files: metrics, glyph outlines for embedding |
| fontconfig | 0.3 | finds installed fonts and substitutes missing ones (Arial → Liberation Sans, …) |
| libeot | 0.0 | fonts embedded in documents in EOT format |

## Images — 2 MB

| library | MB | role |
|---|---:|---|
| libjpeg-turbo, libpng, libtiff, libwebp (+sharpyuv) | 1.5 | decoders for pictures in documents |
| lcms2 | 0.3 | colour management (ICC profiles of pictures, PDF/A output intent) |

## Language support — 23 MB

| library | MB | role |
|---|---:|---|
| ICU data | 13.1 | Unicode data: break rules and dictionaries for line breaking (CJK, Thai, …), normalisation, collation, BiDi (already trimmed from 33 MB) |
| ICU (icuuc, icui18n) | 2.2 | the code using that data |
| i18npool | 2.9 | line/word breaking, character classes, calendars, numbering styles |
| localedata_* | 3.8 | per-locale formats: dates, numbers, currency (e.g. "maandag 5 oktober") |
| lng | 0.3 | linguistic service manager; finds the hyphenator |
| hyphen (+ libhyphen) | 0.05 | hyphenation with the dictionaries in /usr/share/hyphen |
| i18nlangtag, liblangtag, i18nutil | 0.3 | language tags (nl-NL, en-US, …) and Unicode helpers |
| boost_locale | 0.3 | translation of UI strings (English only here) |

## Loading a document — 18 MB

| library | MB | role |
|---|---:|---|
| sfx (sfx2) | 4.6 | document shell: opening and saving documents through filters, document properties |
| fwk (framework) | 2.7 | the desktop, frames and type detection used by loadComponentFromURL; the hidden frame the document is loaded into |
| tk (toolkit) | 1.8 | UNO wrappers for the (hidden) windows of that frame |
| comphelper, utl, tl, svl, svt | 4.0 | shared basics: streams, temp files, configuration access, formatting attributes, number formatter for fields |
| package2, xstor | 1.0 | ZIP packages (.docx and .odt are ZIP files) |
| ucb1, ucpfile1, ucptdoc1, ucbhelper | 1.3 | reading files by URL |
| configmgr | 0.5 | the configuration (compiled-in .xcd files) |
| sot | 0.3 | OLE compound files (.doc files are those) |
| filterconfig, storagefd | 0.3 | which filter reads which file type |
| uui | 0.2 | default interaction handler (LibreOffice requires one; word2pdf answers the questions itself) |
| fsstorage | 0.1 | file system storages |

## XML — 2 MB

| library | MB | role |
|---|---:|---|
| libxml2 | 1.1 | XML parser (also used by liblangtag) |
| unoxml | 0.4 | DOM and XPath (custom XML parts, SmartArt) |
| sax, expat | 0.4 | the fast streaming XML parser .docx is read with |

## UNO component runtime — 4 MB

| library | MB | role |
|---|---:|---|
| sal | 1.9 | system layer: files (including the compiled-in file tree), threads, strings |
| cppuhelper, cppu, salhelper | 0.9 | the UNO component model everything above is built on |
| unoidl, reg, store, xmlreader | 0.5 | reads the type and service registries |
| stocservices, proxyfac, gcc3_uno, components | 0.2 | UNO services, the C++ bridge, the table of linked components |

## Encryption and compression — 4 MB

| library | MB | role |
|---|---:|---|
| libcrypto (OpenSSL) | 3.7 | hashing and AES: opening password-protected/encrypted documents |
| argon2 | 0.0 | key derivation for encrypted .odt |
| zlib | 0.1 | deflate: ZIP packages and PDF stream compression |

## Linked but not used for conversion

Static linking pulls in every object file referenced from an object file that is pulled in, so
code that never runs during a conversion can come along. Removed:

| library | MB | was pulled in by | removed by |
|---|---:|---|---|
| zxcvbn-c | 1.6 | svl PasswordHelper (password strength meter of dialogs) | stub `ZxcvbnMatch` in word2pdf.cxx |
| curl + libssl | 1.3 | lng translate.cxx (DeepL online translation) | `--disable-curl` |
| md4c | 0.05 | sw Markdown import | stub `md_parse` in word2pdf.cxx |

Still in, because cutting them means patching LibreOffice's own code paths (~0.9 MB):

| library | MB | pulled in by | is really for |
|---|---:|---|---|
| dbtools | 0.5 | sw mail merge (SwDBManager) | databases |
| xmlscript | 0.2 | oox VBA controls | Basic dialogs |
| sb | 0.1 | sfx2 application init | the Basic macro runtime (scripting is disabled) |
| avmedia, textconversiondlgs | 0.0 | svx media objects, sw | audio/video, Chinese conversion dialog |

The RDF libraries (librdf, raptor, rasqal, libxslt, unordf; 1.1 MB) look unused for Word
documents, but Writer's PDF export reads paragraph metadata from the RDF repository and fails
without it, so they stay.

## The rest — 11 MB

| part | MB | role |
|---|---:|---|
| embedded files | 8.1 | configuration (.xcd), UNO type and service registries, fontconfig rules, palettes, themes, liblangtag data |
| word2pdf.o | 1.1 | the program itself |
| libstdc++, C runtime, linker data | 2.4 | statically linked C++ runtime |
