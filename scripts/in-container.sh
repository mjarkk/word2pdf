#!/usr/bin/env bash
# Run a command inside the pinned build container with the project mounted at the same path
# (for the work/core development tree, see docs/DEVELOPMENT.md).
#
#   scripts/in-container.sh COMMAND...
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CCACHE="$(absdir "${LO_SLIM_CCACHE:-$ROOT/work/ccache}")"
build_image lo-slim-build "$ROOT/build"
exec_args=(-v "$ROOT:$ROOT" -v "$CCACHE:/ccache" -w "${WORKDIR:-$ROOT}"
           -e SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1767225600}")
container_run "${exec_args[@]}" "${LO_SLIM_IMAGE:-lo-slim-build}" "$@"
