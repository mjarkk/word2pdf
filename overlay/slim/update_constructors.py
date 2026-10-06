#!/usr/bin/env python3
#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Expands slim/components.txt into slim/constructors.list (the linked implementations) and
# slim/component-files.list (the component files whose libraries get linked, see
# solenv/gbuild/static.mk), using the .component files of a finished build. Run after
# changing components.txt:
#
#   slim/update_constructors.py WORKDIR

import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

NS = "{http://openoffice.org/2010/uno-components}"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    workdir = sys.argv[1]
    here = os.path.dirname(os.path.abspath(__file__))

    # Components of a build win; others (not built yet, e.g. just added to components.txt) are
    # read from the source tree.
    srcdir = os.path.dirname(here)
    constructors_of = {}
    for base in (srcdir, os.path.join(workdir, "ComponentTarget")):
        for path in glob.glob(os.path.join(base, "**", "*.component"), recursive=True):
            name = os.path.relpath(path, base)
            if name.startswith(("workdir", "instdir", "repos", "work")):
                continue
            root = ET.parse(path).getroot()
            constructors_of[name] = [i.get("constructor") for i in root.iter(NS + "implementation")
                                     if i.get("constructor")]

    selected = set()
    component_files = set()
    with open(os.path.join(here, "components.txt")) as f:
        for line in f:
            line = line.split("#", 1)[0].split()
            if not line:
                continue
            component, rest = line[0], line[1:]
            if component not in constructors_of:
                sys.exit("unknown component " + component)
            available = constructors_of[component]
            # as gb_Library_set_componentfile names it: sw/util/sw.component -> sw/util/sw
            component_files.add(component[:-len(".component")])
            if not rest:
                selected.update(available)
            elif rest[0].startswith("-"):
                excluded = re.compile(rest[0][1:])
                selected.update(c for c in available if not excluded.search(c))
            else:
                for constructor in rest:
                    if constructor not in available:
                        sys.exit("%s is not in %s" % (constructor, component))
                selected.update(rest)

    with open(os.path.join(here, "constructors.list"), "w") as f:
        f.write("".join(c + "\n" for c in sorted(selected)))
    with open(os.path.join(here, "component-files.list"), "w") as f:
        f.write("".join(c + "\n" for c in sorted(component_files)))
    print("%d constructors from %d components" % (len(selected), len(component_files)))


if __name__ == "__main__":
    main()
