#!/usr/bin/env bash
# Create src/: a standalone source tree with just the parts of LibreOffice word2pdf is built
# from (modules.txt), the libreoffice-slim changes applied (patches/) and its own module added
# (overlay/). src/ is a fresh git repository with one commit, so it can be kept, diffed or
# published as a project of its own.
#
#   scripts/extract.sh [DEST]
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CORE="$ROOT/repos/core"
DEST="$(absdir "${1:-$ROOT/src}")"

"$ROOT/scripts/fetch.sh"
tag=$(sed -n 's/^tag=//p' "$ROOT/LO_VERSION")
commit=$(sed -n 's/^commit=//p' "$ROOT/LO_VERSION")

# The tree is assembled in a staging directory and then synced into DEST, so files that did
# not change keep their timestamps and an existing build of DEST stays incremental.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
modules=$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$ROOT/modules.txt")
# copy from the pinned commit, not the checkout, so local edits in repos/core never leak in
git -C "$CORE" archive --format=tar "$commit" -- $modules | tar -x -C "$STAGE"

# unit tests and their documents are not built here (gbuild tolerates their absence in an
# extracted tree, see patches/0004-gbuild-extracted-trees.patch)
find "$STAGE" -mindepth 2 -maxdepth 2 -type d -name qa -prune -exec rm -rf {} +

cp -a "$ROOT/overlay/." "$STAGE/"
# git apply behaves the same everywhere (BSD and GNU patch do not) and never applies with fuzz
git -C "$STAGE" init -q
for patch in "$ROOT"/patches/*.patch; do
    git -C "$STAGE" apply "$patch"
done

# marks the tree as extracted for gbuild (missing modules are skipped instead of an error)
printf 'libreoffice %s %s\n' "$tag" "$commit" > "$STAGE/.slim-origin"

# One commit with fixed identity and dates, made in the staging repository from exactly the
# staged files (-f: LibreOffice tracks some files its own .gitignore matches): its id only
# depends on the files, and LibreOffice builds it into the executable as the build id.
export GIT_AUTHOR_NAME=libreoffice-slim GIT_AUTHOR_EMAIL=libreoffice-slim@localhost
export GIT_COMMITTER_NAME=libreoffice-slim GIT_COMMITTER_EMAIL=libreoffice-slim@localhost
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
git -C "$STAGE" add -A -f
# Without executable bits in the file system (Windows), git records every file as 644; the
# modes then come from where tar, cp and git apply would have taken them.
if [ "$(git -C "$STAGE" config --bool core.filemode)" = false ]; then
    {
        git -c core.quotePath=false -C "$CORE" ls-tree -r "$commit" -- $modules \
            | awk -F '\t' '$1 ~ /^100755 / { print $2 }'
        git -c core.quotePath=false -C "$ROOT" ls-files -s overlay \
            | awk -F '\t' '$1 ~ /^100755 / { sub(/^overlay\//, "", $2); print $2 }'
        awk '/^diff --git / { path = substr($4, 3) } /^new (file )?mode 100755$/ { print path }' \
            "$ROOT"/patches/*.patch
    } | while IFS= read -r path; do
        if [ -f "$STAGE/$path" ]; then
            printf '%s\n' "$path"
        fi
    done | git -C "$STAGE" update-index --chmod=+x --stdin
fi
git -C "$STAGE" -c core.hooksPath=/dev/null commit -q --no-verify -m "word2pdf sources extracted from LibreOffice $tag ($commit)"

[ -d "$DEST/.git" ] || git -C "$DEST" init -q -b main
git -C "$DEST" fetch -q "$STAGE" HEAD
git -C "$DEST" update-ref refs/heads/main FETCH_HEAD
git -C "$DEST" symbolic-ref HEAD refs/heads/main
# writes only changed or edited files, deletes removed ones, and leaves untracked files (the
# configure autogen.sh makes here) alone
git -C "$DEST" reset -q --hard

echo "$DEST: $(git -C "$DEST" ls-files | wc -l | tr -d ' ') files, commit $(git -C "$DEST" rev-parse --short HEAD)"
