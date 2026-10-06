#!/usr/bin/env python3
"""Download the external library tarballs an extracted tree builds, and only those.

    fetch_tarballs.py SRC_DIR TARBALL_DIR

The tarballs are the ones named by the UnpackedTarball makefiles of the external/ modules and
of slim/ (the fonts) in SRC_DIR, and the files slim/ embeds straight from the tarball directory
(OpenSymbol); file names and SHA-256 sums come from SRC_DIR/download.lst. Existing files are
checked, missing ones downloaded from LibreOffice's mirror. The build runs with
--disable-fetch-external, so nothing else is downloaded.
"""

import hashlib
import os
import re
import subprocess
import sys
import urllib.request

MIRROR = "https://dev-www.libreoffice.org/src/"
# where LibreOffice's Makefile.fetch gets its prebuilt files (*_TTF) from
EXTERN_MIRROR = "https://dev-www.libreoffice.org/extern/"


def make_values(download_lst, names):
    """Expand download.lst variables (they reference each other) with make itself."""
    makefile = "include %s\nprint:\n" % download_lst.replace("\\", "/")
    for name in names:
        makefile += "\t@echo %s=$(%s)\n" % (name, name)
    out = subprocess.run(["make", "-s", "-f", "-", "print"], input=makefile, check=True,
                         capture_output=True, text=True).stdout
    return dict(line.split("=", 1) for line in out.splitlines() if "=" in line)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def fetch(dest, tarball, expected, mirror=MIRROR):
    path = os.path.join(dest, tarball)
    if not os.path.exists(path):
        print("downloading", tarball, flush=True)
        urllib.request.urlretrieve(mirror + tarball, path + ".part")
        os.rename(path + ".part", path)
    if sha256(path) != expected:
        os.remove(path)
        sys.exit("%s: SHA-256 mismatch (removed)" % tarball)
    return path


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dest = sys.argv[1:]
    os.makedirs(dest, exist_ok=True)

    variables = set()
    external = os.path.join(src, "external")
    slim = os.path.join(src, "slim")
    directories = [os.path.join(external, module) for module in sorted(os.listdir(external))]
    for directory in directories + [slim]:
        if not os.path.isdir(directory):
            continue
        for name in os.listdir(directory):
            if not name.endswith(".mk"):
                continue
            with open(os.path.join(directory, name)) as f:
                text = f.read()
            if name.startswith("UnpackedTarball_"):
                variables.update(re.findall(r"gb_UnpackedTarball_set_tarball,[^,]+,\$\((\w+)\)", text))
                # further archives a tarball's unpacking extracts from (ICU's data on Windows)
                variables.update(re.findall(r"\$\(gb_UnpackedTarget_TARFILE_LOCATION\)/\$\((\w+)\)", text))
            if directory == slim:
                variables.update(re.findall(r"\$\(TARFILE_LOCATION\)/\$\((\w+)\)", text))

    sums = {v: v.rsplit("_", 1)[0] + "_SHA256SUM" for v in variables}
    values = make_values(os.path.join(src, "download.lst"), sorted(variables) + sorted(sums.values()))
    for variable in sorted(variables):
        mirror = EXTERN_MIRROR if variable.endswith("_TTF") else MIRROR
        fetch(dest, values[variable], values[sums[variable]], mirror)
    print("%d tarballs in %s" % (len(variables), dest))


if __name__ == "__main__":
    main()
