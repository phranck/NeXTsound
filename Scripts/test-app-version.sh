#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Runs Scripts/app-version.sh against throwaway repositories, one rule at a time, and fails on the first
# version or build number that differs from what the rule says.
scratch=$(mktemp -d "${TMPDIR:-/tmp}/nxs-app-version-test.XXXXXX")
trap 'command rm -rf "$scratch"' EXIT

# The throwaway repositories and app-version.sh read no git configuration from the Mac they run on. A
# global commit.gpgsign would otherwise sign every throwaway commit and fail the test wherever signing
# is unavailable, such as with a locked SSH agent or on a CI host without the signing program.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

repository="$scratch/repository"

start_repository() {
    command rm -rf "$repository"
    git init -q "$repository"
}

commit() {
    git -C "$repository" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m "$1"
}

tag() {
    git -C "$repository" tag "$1"
}

expect() {
    local actual
    actual=$(bash "$root/Scripts/app-version.sh" "$repository")
    if [ "$actual" != "$1" ]; then
        printf 'app-version.sh: %s: expected "%s", found "%s"\n' "$2" "$1" "$actual" >&2
        exit 1
    fi
}

start_repository
commit "Docs: Describe the box"
expect "0.1.0 1" "without an app tag and without Feat or Fix, the version stays at 0.1.0"
commit "Fix: Keep the name"
expect "0.1.1 2" "a Fix commit raises the patch version"
commit "Feat: Show a spectrum"
expect "0.2.0 3" "a Feat commit raises the minor version and resets the patch version"

tag app-v0.2.0
expect "0.2.0 3" "a build of the tagged commit reports the tag's version"
tag firmware-v9.0.0
expect "0.2.0 3" "a tag without the app prefix does not count"

commit "Chore: Update a tool"
expect "0.2.0 4" "without Feat or Fix since the tag, the version stays at the tag's"
commit "Fix: Keep the level"
expect "0.2.1 5" "a Fix commit after the tag raises the patch version"
commit "Feat: Raise the level"
expect "0.3.0 6" "a Feat commit after the tag raises the minor version"

tag app-v0.3.0
commit "Fix: Round the scale"
expect "0.3.1 7" "the latest app tag is the base"

printf 'app-version.sh: all rules hold.\n'
