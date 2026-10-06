#!/usr/bin/env bash
# Print the version of the next word2pdf release: LibreOffice-<version>-B<n>, with the
# LibreOffice version from LO_VERSION and n one more than the highest number ending a GitHub
# release tag that starts with LibreOffice-<version>- (drafts included), so 1 for the first
# release on a LibreOffice version.
#
#   scripts/next-version.sh
#
# Needs the GitHub CLI, logged in (gh auth login) or with GH_TOKEN set.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

prefix="LibreOffice-$(sed -n 's/^tag=libreoffice-//p' "$ROOT/LO_VERSION")-"
# gh fills in {owner}/{repo} from the git remote of the current directory
cd "$ROOT"
last="$(gh api --paginate 'repos/{owner}/{repo}/releases' --jq '.[].tag_name' | awk -v prefix="$prefix" '
    index($0, prefix) == 1 && match($0, /[0-9]+$/) { n = substr($0, RSTART) + 0; if (n > max) max = n }
    END { print max + 0 }')"
echo "${prefix}B$((last + 1))"
