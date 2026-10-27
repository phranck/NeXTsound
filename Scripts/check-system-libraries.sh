#!/bin/bash
# Fails when a Mach-O file loads a library from outside macOS and its own bundle, because the app
# has to run self-contained and must not load code from a directory a user-level process can write.
# Takes files or directories; a directory is searched for every Mach-O file inside it.
set -euo pipefail

allowed='^(/System/Library/|/usr/lib/|@rpath/|@executable_path(/|$)|@loader_path(/|$))'
failures=0

check() {
    local binary=$1
    local libraries rpaths
    libraries=$(otool -L "$binary" | tail -n +2 | awk '{ print $1 }')
    rpaths=$(otool -l "$binary" | awk '$1 == "cmd" { command = $2 } command == "LC_RPATH" && $1 == "path" { print $2 }')
    for path in $libraries $rpaths; do
        if [[ ! $path =~ $allowed ]]; then
            printf '%s loads %s from outside macOS and its bundle.\n' "$binary" "$path" >&2
            failures=$((failures + 1))
        fi
    done
}

for target in "$@"; do
    if [ -d "$target" ]; then
        while IFS= read -r -d '' candidate; do
            if file -b "$candidate" | grep -q '^Mach-O'; then
                check "$candidate"
            fi
        done < <(find "$target" -type f -print0)
    else
        check "$target"
    fi
done

if [ "$failures" -gt 0 ]; then
    exit 1
fi
