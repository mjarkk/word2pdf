#!/usr/bin/env python3
#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Drops the implementations from a services.rdb whose constructor function is not linked
# into the executable, so that asking for them behaves like an uninstalled service
# instead of failing to construct.
#
#   filter_services.py INPUT.rdb CONSTRUCTORS.list OUTPUT.rdb

import sys
import xml.etree.ElementTree as ET

NS = "http://openoffice.org/2010/uno-components"


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    source, constructors_file, output = sys.argv[1:]
    with open(constructors_file) as f:
        constructors = {line.strip() for line in f if line.strip() and not line.startswith("#")}

    ET.register_namespace("", NS)
    tree = ET.parse(source)
    root = tree.getroot()
    for component in list(root.findall("{%s}component" % NS)):
        implementations = component.findall("{%s}implementation" % NS)
        # Implementations without a constructor come from a component_getFactory function
        # (lo_get_factory_map); those stay.
        if not any(i.get("constructor") for i in implementations):
            continue
        for implementation in implementations:
            if implementation.get("constructor") not in constructors:
                component.remove(implementation)
        if not component.findall("{%s}implementation" % NS):
            root.remove(component)
    tree.write(output, xml_declaration=True, encoding="UTF-8")


if __name__ == "__main__":
    main()
