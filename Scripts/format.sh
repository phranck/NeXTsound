#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
select_xcode

mode=${1:---check}
if [ "$mode" != --check ] && [ "$mode" != --write ] && [ "$mode" != --fixtures ]; then
    printf 'Usage: bash Scripts/format.sh [--check|--write|--fixtures]\n' >&2
    exit 1
fi
bash "$root/Scripts/bootstrap-tools.sh"
compiler=$(xcrun --find swiftc)
host="$(dirname "$compiler")/../lib/swift/host"
layout="$root/.tools/bin/swift-layout"
if [ ! -x "$layout" ] || [ "$root/Scripts/swift-layout.swift" -nt "$layout" ] || [ "$manifest" -nt "$layout" ]; then
    xcrun swiftc -swift-version 6 -I "$host" -L "$host" -lSwiftSyntax -lSwiftParser \
        -Xlinker -rpath -Xlinker "$host" "$root/Scripts/swift-layout.swift" -o "$layout"
fi

temporary=$(mktemp -d "${TMPDIR:-/tmp}/NeXTsound-format.XXXXXX")
trap 'command rm -rf "$temporary"' EXIT

format_swift() {
    local input="$1" output="$2"
    "$layout" < "$input" > "$temporary/layout.swift"
    "$root/.tools/bin/swiftformat" stdin --quiet --config "$root/.swiftformat" \
        --output "$output" < "$temporary/layout.swift"
}

if [ "$mode" = --fixtures ]; then
    format_swift "$root/Scripts/Fixtures/layout.input" "$temporary/result.swift"
    diff -u "$root/Scripts/Fixtures/layout.expected" "$temporary/result.swift"
    format_swift "$temporary/result.swift" "$temporary/repeated.swift"
    diff -u "$temporary/result.swift" "$temporary/repeated.swift"
    if printf 'let =' | "$layout" > "$temporary/invalid.swift" 2> "$temporary/invalid.log"; then
        printf 'The syntax formatter accepted invalid Swift.\n' >&2
        exit 1
    fi
    printf 'Swift layout regression cases passed.\n'
    exit 0
fi

count=0
while IFS= read -r -d '' relative; do
    input="$root/$relative"
    format_swift "$input" "$temporary/result.swift"
    if ! cmp -s "$input" "$temporary/result.swift"; then
        if [ "$mode" = --write ]; then
            cp "$temporary/result.swift" "$input"
        else
            diff -u "$input" "$temporary/result.swift" || true
            exit 1
        fi
    fi
    count=$((count + 1))
done < <(swift_sources)

while IFS= read -r -d '' relative; do
    if [ "$mode" = --write ]; then
        xcrun clang-format -i "$root/$relative"
    else
        xcrun clang-format --dry-run --Werror "$root/$relative"
    fi
done < <(c_sources)
printf 'Source formatting %s completed for %s Swift files.\n' "$mode" "$count"
