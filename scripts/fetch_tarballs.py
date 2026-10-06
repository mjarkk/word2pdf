#!/usr/bin/env python3
"""Download the external library tarballs an extracted tree builds, and only those.

    fetch_tarballs.py SRC_DIR TARBALL_DIR

The tarballs are the ones named by the UnpackedTarball makefiles of the external/ modules in
SRC_DIR; file names and SHA-256 sums come from SRC_DIR/download.lst. Existing files are
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


def fetch(dest, tarball, expected):
    path = os.path.join(dest, tarball)
    if not os.path.exists(path):
        print("downloading", tarball, flush=True)
        urllib.request.urlretrieve(MIRROR + tarball, path + ".part")
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
    for module in sorted(os.listdir(external)):
        directory = os.path.join(external, module)
        if not os.path.isdir(directory):
            continue
        for name in os.listdir(directory):
            if name.startswith("UnpackedTarball_") and name.endswith(".mk"):
                with open(os.path.join(directory, name)) as f:
                    text = f.read()
                variables.update(re.findall(r"gb_UnpackedTarball_set_tarball,[^,]+,\$\((\w+)\)", text))
                # further archives a tarball's unpacking extracts from (ICU's data on Windows)
                variables.update(re.findall(r"\$\(gb_UnpackedTarget_TARFILE_LOCATION\)/\$\((\w+)\)", text))

    sums = {v: v.rsplit("_", 1)[0] + "_SHA256SUM" for v in variables}
    values = make_values(os.path.join(src, "download.lst"), sorted(variables) + sorted(sums.values()))
    for variable in sorted(variables):
        fetch(dest, values[variable], values[sums[variable]])
    print("%d tarballs in %s" % (len(variables), dest))


if __name__ == "__main__":
    main()
