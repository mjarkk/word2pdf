# Test data

* `corpus/`: documents converted by `scripts/test.sh`:
  * 108 documents from LibreOffice's own test suite (`sw/qa/extras/*/data` of the pinned
    version; MPL-2.0), picked to cover docx, doc, rtf and odt with charts, formulas, SmartArt,
    fields, tracked changes and more;
  * `sample-docx-files-sample1.docx`, calibre's DOCX demo by Kovid Goyal
    (<https://calibre-ebook.com/downloads/demos/demo.docx>), which is published without
    license terms;
  * `multilingual.docx` (Thai, Chinese, Japanese, Korean, Arabic, Hebrew, Hindi line breaking)
    and `hyphenation.docx` (automatic hyphenation in English and Dutch), made for this project.
* `corpus-ref/`: the same documents converted by a regular LibreOffice of the same version with
  word2pdf's PDF options and font configuration (`scripts/make-references.sh`).
* `fonts.conf`: word2pdf's compiled-in fontconfig configuration, for making the references:
  fontconfig's own configuration files (fontconfig's MIT-style license) and LibreOffice's
  snippets (MPL-2.0), combined by `overlay/slim/make_fonts_conf.py`.
* `locale/`: documents whose date fields must come out in Dutch and German; checked by weekday
  name only, because DATE fields show the current date. Made for this project.

The documents made for this project are under the repository's MPL-2.0; the PDFs in
`corpus-ref/` are under the terms of the documents they were converted from.
