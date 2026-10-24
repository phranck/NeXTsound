#!/bin/bash

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manifest="$root/toolchain.json"

select_xcode() {
    local version build expected actual candidate
    version=$(jq -r '.xcode.version' "$manifest")
    build=$(jq -r '.xcode.build' "$manifest")
    expected=$(printf 'Xcode %s\nBuild version %s' "$version" "$build")
    actual=$(xcodebuild -version)
    if [ "$actual" != "$expected" ]; then
        candidate="/Applications/Xcode_${version}.app/Contents/Developer"
        if [ -d "$candidate" ]; then
            export DEVELOPER_DIR="$candidate"
            actual=$(xcodebuild -version)
        fi
    fi
    if [ "$actual" != "$expected" ]; then
        printf 'Expected %s, found %s\n' "$expected" "$actual" >&2
        return 1
    fi
}

tool_executable() {
    local executable="$root/.tools/bin/$1"
    if [ -L "$executable" ]; then
        readlink "$executable"
    else
        printf '%s\n' "$executable"
    fi
}

tool_version() {
    local tool="$1" argument prefix actual executable
    argument=$(jq -r --arg tool "$tool" '.tools[$tool].version_argument' "$manifest")
    prefix=$(jq -r --arg tool "$tool" '.tools[$tool].version_prefix // ""' "$manifest")
    executable=$(tool_executable "$tool")
    actual=$("$executable" "$argument")
    printf '%s\n' "${actual#"$prefix"}"
}

swift_sources() {
    git -C "$root" ls-files -z --cached --others --exclude-standard -- '*.swift'
}

c_sources() {
    git -C "$root" ls-files -z --cached --others --exclude-standard -- '*.c' '*.h'
}
