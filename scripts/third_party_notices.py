#!/usr/bin/env python3
"""Write the license notices that have to accompany a word2pdf executable.

    third_party_notices.py CORE_DIR TARBALL_DIR OUTPUT

CORE_DIR is the LibreOffice tree at the pinned tag (repos/core). License texts are copied
verbatim from the tarballs download.lst names, so they match the versions built (missing ones
are downloaded into TARBALL_DIR), and from LibreOffice's own tree.

COMPONENTS is what ends up in the executable, which is less than what the build compiles: the
symbols of a linked word2pdf show which libraries contribute code (see docs/LIBRARIES.md).
Check it again after changing modules.txt, slim/components.txt or the configure options.
"""

import html
import os
import re
import sys
import tarfile
import textwrap

from fetch_tarballs import MIRROR, fetch, make_values

REPOSITORY = "https://github.com/mjarkk/word-to-pdf-converter"

# (name, its download.lst variable or its path in LibreOffice's tree, license word2pdf is
#  distributed under, the licenses it was chosen from, files with the license terms)
# A file is a path below the tarball's top directory (or in CORE_DIR), or (path, first, end):
# the lines from the first one matching the regex FIRST up to the next one matching END.
COMPONENTS = [
    ("Argon2", "ARGON2_TARBALL", "CC0-1.0 or Apache-2.0", None, ["LICENSE"]),
    ("Boost", "BOOST_TARBALL", "BSL-1.0", None, ["LICENSE_1_0.txt"]),
    ("cairo", "CAIRO_TARBALL", "MPL-1.1", "LGPL-2.1 or MPL-1.1", ["COPYING", "COPYING-MPL-1.1"]),
    ("Dragonbox", "DRAGONBOX_TARBALL", "BSL-1.0", "Apache-2.0 WITH LLVM-exception or BSL-1.0",
     ["LICENSE-Boost"]),
    ("Expat", "EXPAT_TARBALL", "MIT", None, ["COPYING"]),
    ("fast_float", "FAST_FLOAT_TARBALL", "MIT", "Apache-2.0, BSL-1.0 or MIT", ["LICENSE-MIT"]),
    ("fontconfig", "FONTCONFIG_TARBALL", "MIT-style", None, ["COPYING"]),
    ("FreeType", "FREETYPE_TARBALL", "FreeType License", "FreeType License or GPL-2.0",
     ["LICENSE.TXT", "docs/FTL.TXT"]),
    ("frozen", "FROZEN_TARBALL", "Apache-2.0", None, ["LICENSE"]),
    ("Graphite2", "GRAPHITE_TARBALL", "MPL-2.0", "LGPL-2.1+, MPL-2.0 or GPL-2.0+", ["COPYING"]),
    ("HarfBuzz", "HARFBUZZ_TARBALL", "MIT-style", None, ["COPYING"]),
    ("Hyphen", "HYPHEN_TARBALL", "MPL-1.1", "GPL-2.0+, LGPL-2.1+ or MPL-1.1+",
     ["COPYING", "COPYING.MPL"]),
    ("ICU", "ICU_TARBALL", "Unicode-3.0 and the terms in its LICENSE", None, ["LICENSE"]),
    ("ICU data", "ICU_DATA_TARBALL", "as ICU", None, []),
    ("IANA Language Subtag Registry", "LANGTAGREG_TARBALL", "none (registry data)", None, []),
    ("libeot", "LIBEOT_TARBALL", "MPL-2.0", None, ["LICENSE", "PATENTS"]),
    ("libfixmath", "tools/source/misc/fix16.cxx", "MIT", None,
     [("tools/source/misc/fix16.cxx", r"libfixmath is Copyright", r"\*/")]),
    ("libjpeg-turbo", "LIBJPEG_TURBO_TARBALL", "IJG and BSD-3-Clause", None,
     ["LICENSE.md", ("README.ijg", r"^LEGAL ISSUES$", r"^REFERENCES$")]),
    ("liblangtag", "LIBLANGTAG_TARBALL", "MPL-2.0", "LGPL-3.0+ or MPL-2.0",
     [("README", r"^Licensing$", r"^References$")]),
    ("libpng", "LIBPNG_TARBALL", "libpng-2.0", None, ["LICENSE"]),
    ("LibTIFF", "LIBTIFF_TARBALL", "libtiff", None, ["LICENSE.md"]),
    ("libwebp", "LIBWEBP_TARBALL", "BSD-3-Clause", None, ["COPYING", "PATENTS"]),
    ("libxml2", "LIBXML_TARBALL", "MIT", None, ["Copyright"]),
    ("libxslt", "LIBXSLT_TARBALL", "MIT", None, ["Copyright"]),
    ("Little CMS", "LCMS2_TARBALL", "MIT", None, ["LICENSE"]),
    ("mdds", "MDDS_TARBALL", "MIT", None, ["LICENSE"]),
    ("OpenSSL", "OPENSSL_TARBALL", "Apache-2.0", None, ["LICENSE.txt"]),
    ("pixman", "PIXMAN_TARBALL", "MIT", None, ["COPYING"]),
    ("Raptor", "RAPTOR_TARBALL", "Apache-2.0", "LGPL-2.1+, GPL-2.0+ or Apache-2.0",
     ["LICENSE.txt", "LICENSE-2.0.txt", "NOTICE"]),
    ("Rasqal", "RASQAL_TARBALL", "Apache-2.0", "LGPL-2.1+, GPL-2.0+ or Apache-2.0",
     ["LICENSE.txt", "LICENSE-2.0.txt", "NOTICE"]),
    ("Redland", "REDLAND_TARBALL", "Apache-2.0", "LGPL-2.1+, GPL-2.0+ or Apache-2.0",
     ["LICENSE.txt", "LICENSE-2.0.txt", "NOTICE"]),
    ("Unicode CLDR data", "i18npool/source/localedata/data", "Unicode License", None,
     [("readlicense_oo/license/license.xml", r"<h2>Unicode CLDR data repository</h2>",
       r"</div>")]),
    ("zlib", "ZLIB_TARBALL", "Zlib", None, ["LICENSE"]),
]

HEADER = """\
word2pdf: licenses and notices
==============================

word2pdf is LibreOffice's Writer and PDF export built as one executable, with the libraries
listed below linked in. It is distributed under the Mozilla Public License 2.0, like
LibreOffice; each library keeps its own license. Where a library offers a choice of licenses,
the one named here is the one word2pdf is distributed under.

The source code of everything in the executable:

  word2pdf        {repository}
                  (build files, and the changes to LibreOffice in overlay/ and patches/)
  LibreOffice     {url}, tag {tag}
  the libraries   the tarballs named below, from {mirror},
                  with the patches in LibreOffice's external/<library>/ applied

This software is based in part on the work of the Independent JPEG Group.

Portions of this software are copyright © {freetype_year} The FreeType Project
(www.freetype.org). All rights reserved.

The Linux executable also contains the GCC runtime libraries (libstdc++, libgcc), whose
license, GPL-3.0 with the GCC Runtime Library Exception, places no conditions on programs
compiled with GCC.
"""

def decode(data):
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("latin-1")


def tarball_files(tarball, paths):
    """{path: (name in the tarball, text)} for PATHS below the top directory of TARBALL."""
    found = {}
    with tarfile.open(tarball) as tar:
        for member in tar:
            path = member.name.partition("/")[2]
            if path in paths and path not in found:
                found[path] = (member.name, decode(tar.extractfile(member).read()))
                if len(found) == len(paths):
                    break
    missing = sorted(set(paths) - set(found))
    if missing:
        sys.exit("%s: no %s" % (os.path.basename(tarball), ", ".join(missing)))
    return found


def excerpt(text, first, end):
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if re.search(first, line))
    stop = next(i for i in range(start + 1, len(lines)) if re.search(end, lines[i]))
    return "\n".join(lines[start:stop])


def paragraphs(xhtml):
    """The text of the <p> elements of LibreOffice's license.xml, without its own links."""
    out = []
    for p in re.findall(r"<p\b[^>]*>(.*?)</p>", xhtml, re.S):
        text = " ".join(html.unescape(re.sub(r"<[^>]+>", "", p)).split())
        if not text.startswith("Jump to"):
            out.append(textwrap.fill(text, 95))
    return "\n\n".join(out)


def is_tarball(source):
    return source.endswith("_TARBALL")


def license_terms(core, tarball, files):
    """[(label, text)] for the FILES of a component."""
    if not files:
        return []
    paths = [f if isinstance(f, str) else f[0] for f in files]
    if tarball:
        found = tarball_files(tarball, set(paths))
    else:
        found = {}
        for path in paths:
            with open(os.path.join(core, path), "rb") as f:
                found[path] = (path, decode(f.read()))
    terms = []
    for f in files:
        name, text = found[f if isinstance(f, str) else f[0]]
        if not isinstance(f, str):
            text = excerpt(text, f[1], f[2])
            name += " (excerpt)"
            if f[0].endswith(".xml"):
                text = paragraphs(text)
            elif f[0].endswith(".cxx"):
                text = "\n".join(re.sub(r"^ \* ?", "", line) for line in text.splitlines())
        terms.append((name, text))
    return terms


def heading(title):
    return "\n\n%s\n%s\n\n" % (title, "=" * len(title))


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    core, tarball_dir, output = sys.argv[1:]
    os.makedirs(tarball_dir, exist_ok=True)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(os.path.join(root, "LO_VERSION")) as f:
        version = dict(line.split("=", 1) for line in f.read().split())

    variables = sorted(c[1] for c in COMPONENTS if is_tarball(c[1]))
    sums = {v: v[: -len("_TARBALL")] + "_SHA256SUM" for v in variables}
    values = make_values(os.path.join(core, "download.lst"), variables + sorted(sums.values()))
    tarballs = {v: fetch(tarball_dir, values[v], values[sums[v]]) for v in variables}

    with open(os.path.join(core, "COPYING.MPL")) as f:
        mpl = f.read()
    apache = tarball_files(tarballs["OPENSSL_TARBALL"], {"LICENSE.txt"})["LICENSE.txt"][1]
    ftheader = tarball_files(tarballs["FREETYPE_TARBALL"], {"include/freetype/freetype.h"})
    freetype_year = re.search(r"Copyright \(C\) \d{4}-(\d{4})",
                              ftheader["include/freetype/freetype.h"][1]).group(1)

    def key(text):
        return " ".join(text.split())

    printed = {key(mpl): "the Mozilla Public License 2.0 at the end of this file",
               key(apache): "the Apache License 2.0 at the end of this file"}

    components = sorted(COMPONENTS, key=lambda c: c[0].lower())
    rows = [("LibreOffice", "MPL-2.0, parts also Apache-2.0")]
    rows += [(name, used) for name, _, used, _, _ in components]
    width = max(len(name) for name, _ in rows)

    with open(output, "w") as out:
        out.write(HEADER.format(repository=REPOSITORY, url=version["url"], tag=version["tag"],
                                mirror=MIRROR, freetype_year=freetype_year))
        out.write("\n%-*s  %s\n" % (width, "Component", "License"))
        for name, used in rows:
            out.write("%-*s  %s\n" % (width, name, used))

        out.write(heading("LibreOffice"))
        out.write("Source:  %s, tag %s\n" % (version["url"], version["tag"]))
        out.write("License: MPL-2.0; the files LibreOffice inherited from OpenOffice.org are also\n"
                  "         under the Apache License 2.0. Both are at the end of this file.\n\n")
        with open(os.path.join(core, "readlicense_oo/license/license.xml")) as f:
            out.write(paragraphs(excerpt(f.read(), r"<h1\b", r"<h2>Contents</h2>")) + "\n\n")
        with open(os.path.join(core, "readlicense_oo/license/NOTICE")) as f:
            out.write("readlicense_oo/license/NOTICE:\n\n" + f.read().rstrip() + "\n")

        for name, source, used, choice, files in components:
            out.write(heading(name))
            if is_tarball(source):
                out.write("Source:  %s%s\n" % (MIRROR, values[source]))
            else:
                out.write("Source:  LibreOffice, %s\n" % source)
            out.write("License: %s%s\n" % (used, ", chosen from " + choice if choice else ""))
            for label, text in license_terms(core, tarballs.get(source), files):
                out.write("\n%s:\n\n" % label)
                if key(text) in printed:
                    out.write("Identical to %s.\n" % printed[key(text)])
                else:
                    printed[key(text)] = label + " above"
                    out.write(text.strip("\n") + "\n")

        out.write(heading("Mozilla Public License 2.0") + mpl.strip("\n") + "\n")
        out.write(heading("Apache License 2.0") + apache.strip("\n") + "\n")


if __name__ == "__main__":
    main()
