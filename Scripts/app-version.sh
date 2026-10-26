#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Prints the app's version and build number, separated by a space, from the git history of the given
# repository, this one by default. The firmware keeps a version of its own in Firmware/CMakeLists.txt.
#
# The build number counts the commits reachable from HEAD, so it grows along main. The version is the one
# in the app tag on HEAD, app-vMAJOR.MINOR.PATCH. Otherwise it follows the latest app tag before HEAD: a
# Feat: commit since then raises the minor version, and otherwise a Fix: commit raises the patch version.
# Without any app tag, it counts from 0.1.0.
repository="${1:-$root}"
tag_prefix="app-v"
version="0.1.0"
range=HEAD

build=$(git -C "$repository" rev-list --count HEAD)
latest_tag=$(git -C "$repository" describe --tags --abbrev=0 --match "${tag_prefix}[0-9]*" 2>/dev/null || true)
if [ -n "$latest_tag" ]; then
    version=${latest_tag#"$tag_prefix"}
    range="$latest_tag..HEAD"
fi

subjects=$(git -C "$repository" log --format=%s "$range")
IFS=. read -r major minor patch <<< "$version"
if grep -q '^Feat:' <<< "$subjects"; then
    minor=$((minor + 1))
    patch=0
elif grep -q '^Fix:' <<< "$subjects"; then
    patch=$((patch + 1))
fi
printf '%s.%s.%s %s\n' "$major" "$minor" "$patch" "$build"
