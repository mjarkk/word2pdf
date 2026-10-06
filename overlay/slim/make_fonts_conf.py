#!/usr/bin/env python3
#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Writes one self-contained fontconfig configuration: font and cache directories, the
# rules of fontconfig's default fonts.conf and its default-enabled conf.d files,
# LibreOffice's own snippets and LAST_RULES. Nothing in it includes other files, so the
# result can be loaded from memory without reading /etc/fonts.
#
#   make_fonts_conf.py [--os=OS] OUTPUT FONTCONFIG_SRCDIR SNIPPET...
#
# OS is gbuild's $(OS); it picks the system font directories (default LINUX).

import os
import sys
import re

# fontconfig's conf.d/Makefile.am CONF_LINKS, minus the per-user and per-host includes
# (50-user, 51-local); hinting and sub-pixel choices do not matter for PDF output.
DEFAULT_CONFS = [
    "10-hinting-slight.conf",
    "10-scale-bitmap-fonts.conf",
    "10-yes-antialias.conf",
    "10-sub-pixel-none.conf",
    "11-lcdfilter-default.conf",
    "20-unhint-small-vera.conf",
    "30-metric-aliases.conf",
    "40-nonlatin.conf",
    "45-generic.conf",
    "45-latin.conf",
    "48-guessfamily.conf",
    "48-spacing.conf",
    "49-sansserif.conf",
    "60-generic.conf",
    "60-latin.conf",
    "65-fonts-persian.conf",
    "65-nonlatin.conf",
    "69-unifont.conf",
    "80-delicious.conf",
    "90-synthetic.conf",
]

FONT_DIRS = {
    "LINUX": [
        "/usr/share/fonts",
        "/usr/local/share/fonts",
    ],
    # CoreText's directories, without the fonts macOS downloads on demand (their
    # MobileAsset directory is versioned)
    "MACOSX": [
        "/System/Library/Fonts",
        "/Library/Fonts",
        "~/Library/Fonts",
    ],
}

HEADER = """<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
%s\t<dir prefix="xdg">fonts</dir>
\t<dir>~/.fonts</dir>
\t<cachedir>/var/cache/fontconfig</cachedir>
\t<cachedir prefix="xdg">fontconfig</cachedir>
\t<cachedir>~/.fontconfig</cachedir>
"""

# fontconfig 2.17 ranks the generic family (guessed from a font's name: "Noto Sans" is
# sans-serif, "Carlito" is unknown) above the requested family, and VCL asks for "sans" or
# "serif" with every name, so "Calibri Light" got any "... Sans" font over the Carlito its
# aliases name. Without it in the request, matching is as in fontconfig 2.15.
LAST_RULES = """\t<match target="pattern">
\t\t<edit name="genericfamily" mode="delete_all"/>
\t</match>
"""

# Elements that would make fontconfig read further files or that are set in HEADER.
# fontconfig's files are not namespace-clean XML (they use xsi: undeclared), so this works
# on the text instead of parsing it.
SKIPPED = re.compile(
    r"<\?xml[^>]*\?>|<!DOCTYPE[^>]*>|</?fontconfig>"
    r"|<(description|dir|cachedir|include|config)\b[^>]*?/>"
    r"|<(description|dir|cachedir|include|config)\b.*?</\2>",
    re.DOTALL)


def rules(path):
    with open(path, encoding="utf-8") as f:
        text = SKIPPED.sub("", f.read())
    text = re.sub(r"\n\s*\n+", "\n", text).strip("\n")
    if text.strip():
        yield text + "\n"


def main():
    args = sys.argv[1:]
    system = "LINUX"
    if args and args[0].startswith("--os="):
        system = args.pop(0)[len("--os="):]
    if len(args) < 2 or system not in FONT_DIRS:
        sys.exit(__doc__)
    output, srcdir = args[0], args[1]
    parts = [HEADER % "".join("\t<dir>%s</dir>\n" % d for d in FONT_DIRS[system])]
    sources = [os.path.join(srcdir, "fonts.conf")]
    sources += [os.path.join(srcdir, "conf.d", name) for name in DEFAULT_CONFS]
    sources += args[2:]
    for source in sources:
        parts.append("\t<!-- %s -->\n" % os.path.basename(source))
        parts.extend(rules(source))
    parts.append(LAST_RULES + "</fontconfig>\n")
    with open(output, "w", encoding="utf-8") as f:
        f.write("".join(parts))


if __name__ == "__main__":
    main()
