# Shared by the scripts: the container engine and path helpers that also work with macOS's
# bash 3.2 and BSD tools.
#
#   LO_SLIM_ENGINE    podman or docker (default: podman if installed, else docker)
#   LO_SLIM_PLATFORM  container platform, e.g. linux/amd64 to build x86-64 on Apple Silicon
#   LO_SLIM_VOLUMES   1: keep the build directory, the compiler cache and a copy of the sources in
#                     named volumes instead of work/ and src/ (default on macOS, where they are
#                     on the Linux file system of the container VM: much faster than a bind
#                     mount, and case-sensitive)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="${LO_SLIM_ENGINE:-$(command -v podman >/dev/null 2>&1 && echo podman || echo docker)}"

# absolute path of a directory, created if missing
absdir() {
    mkdir -p "$1" && (cd "$1" && pwd)
}

use_volumes() {
    local default=0
    if [ "$(uname -s)" = Darwin ]; then
        default=1
    fi
    [ "${LO_SLIM_VOLUMES:-$default}" = 1 ]
}

# `$ENGINE run` with files created in mounted directories owned by the calling user
container_run() {
    local args=(run --rm -i -e HOME=/tmp)
    if [ "$ENGINE" = podman ]; then
        args+=(--userns=keep-id --security-opt label=disable)
    else
        args+=(--user "$(id -u):$(id -g)")
    fi
    if [ -n "${LO_SLIM_PLATFORM:-}" ]; then
        args+=(--platform "$LO_SLIM_PLATFORM")
    fi
    "$ENGINE" "${args[@]}" "$@"
}

# build an image from a directory with a Containerfile:
#   build_image NAME DIR [TARGET [MORE BUILD OPTIONS...]]
build_image() {
    local name="$1" dir="$2" target="${3:-}"
    local args=(build -q -t "$name" -f "$dir/Containerfile")
    if [ -n "$target" ]; then
        args+=(--target "$target")
    fi
    if [ -n "${LO_SLIM_PLATFORM:-}" ]; then
        args+=(--platform "$LO_SLIM_PLATFORM")
    fi
    shift $(($# < 3 ? $# : 3))
    "$ENGINE" "${args[@]}" "$@" "$dir" >/dev/null
}

# file name in out/ for an OS and a uname -m architecture:
#   binary_name linux aarch64 -> word2pdf-linux-arm64
binary_name() {
    local arch="$2"
    [ "$arch" != aarch64 ] || arch=arm64
    echo "word2pdf-$1-$arch"
}

# the architecture the containers run, as uname -m says it (x86_64, aarch64)
container_arch() {
    container_run lo-slim-build uname -m
}
