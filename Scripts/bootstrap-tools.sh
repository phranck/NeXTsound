#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/NeXTsound-tools.XXXXXX")
trap 'command rm -rf "$temporary"' EXIT
mkdir -p "$root/.tools/bin" "$root/.tools/packages"

while IFS= read -r tool; do
    version=$(jq -r --arg tool "$tool" '.tools[$tool].version' "$manifest")
    version_argument=$(jq -r --arg tool "$tool" '.tools[$tool].version_argument' "$manifest")
    executable="$root/.tools/bin/$tool"
    if [ -x "$executable" ] && [ "$("$executable" "$version_argument")" = "$version" ]; then
        continue
    fi
    url=$(jq -r --arg tool "$tool" '.tools[$tool].url' "$manifest")
    checksum=$(jq -r --arg tool "$tool" '.tools[$tool].sha256' "$manifest")
    license_url=$(jq -r --arg tool "$tool" '.tools[$tool].license_url' "$manifest")
    archive="$temporary/$tool.zip"
    package="$root/.tools/packages/$tool-$version"
    curl --fail --location --silent --show-error --retry 3 "$url" --output "$archive"
    printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c -
    mkdir -p "$package"
    unzip -q -o "$archive" -d "$package"
    binary=$(find "$package" -type f -name "$tool" -print -quit)
    if [ -z "$binary" ]; then
        printf 'No %s executable in %s\n' "$tool" "$url" >&2
        exit 1
    fi
    curl --fail --location --silent --show-error --retry 3 "$license_url" --output "$package/LICENSE"
    chmod +x "$binary"
    ln -sfn "$binary" "$executable"
    actual=$("$executable" "$version_argument")
    if [ "$actual" != "$version" ]; then
        printf 'Expected %s %s, found %s\n' "$tool" "$version" "$actual" >&2
        exit 1
    fi
    printf '%s %s ready\n' "$tool" "$version"
done < <(jq -r '.tools | keys[]' "$manifest")
