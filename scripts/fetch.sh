#!/usr/bin/env bash
# Clone the pinned LibreOffice tree (LO_VERSION) into repos/core and check it is the expected
# commit. The external library tarballs are downloaded, and checked against the SHA-256 sums in
# download.lst, by the build itself.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tag=$(sed -n 's/^tag=//p' "$ROOT/LO_VERSION")
commit=$(sed -n 's/^commit=//p' "$ROOT/LO_VERSION")
url=$(sed -n 's/^url=//p' "$ROOT/LO_VERSION")
core="$ROOT/repos/core"

if [ ! -d "$core/.git" ]; then
    git clone --depth 1 --branch "$tag" "$url" "$core"
fi
actual=$(git -C "$core" rev-parse "refs/tags/$tag^{commit}" 2>/dev/null || git -C "$core" rev-parse HEAD)
if [ "$actual" != "$commit" ]; then
    echo "repos/core: $tag is $actual, expected $commit" >&2
    exit 1
fi
echo "repos/core: $tag ($commit)"
