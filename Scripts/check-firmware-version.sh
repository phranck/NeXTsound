#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Capabilities report the version number from Firmware/CMakeLists.txt, so a branch that changes what
# goes into the firmware has to raise it. Otherwise two different firmwares report the same number.
# The comparison runs against the merge base with the given reference, origin/main by default.
base_ref="${1:-origin/main}"
firmware_paths=(Firmware ':!Firmware/Tests' Shared/CMakeLists.txt Shared/Sources/NeXTsoundProtocol Shared/Sources/NeXTsoundDSP)

if ! git -C "$root" rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null; then
    printf '%s is not available, so the firmware version cannot be compared\n' "$base_ref" >&2
    exit 1
fi
base=$(git -C "$root" merge-base HEAD "$base_ref")

version_in() {
    sed -nE 's/^project\(NeXTsoundFirmware VERSION ([0-9]+\.[0-9]+\.[0-9]+) .*/\1/p'
}
current=$(version_in < "$root/Firmware/CMakeLists.txt")
previous=$(git -C "$root" show "$base:Firmware/CMakeLists.txt" | version_in)
if [ -z "$current" ]; then
    printf 'Firmware/CMakeLists.txt declares no MAJOR.MINOR.PATCH project version\n' >&2
    exit 1
fi

# toolchain.json also pins Xcode and the Swift tools, so only its firmware section counts.
changed=false
if ! git -C "$root" diff --quiet "$base" -- "${firmware_paths[@]}"; then
    changed=true
elif [ "$(git -C "$root" show "$base:toolchain.json" | jq -S .firmware)" != "$(jq -S .firmware "$manifest")" ]; then
    changed=true
fi

if [ "$changed" = true ] && [ -n "$previous" ]; then
    newest=$(printf '%s\n%s\n' "$previous" "$current" | sort -V | tail -n 1)
    if [ "$current" = "$previous" ] || [ "$newest" != "$current" ]; then
        printf 'The firmware changed since %s, but its version %s does not raise %s. Raise it in Firmware/CMakeLists.txt.\n' \
            "$(git -C "$root" rev-parse --short=8 "$base")" "$current" "$previous" >&2
        exit 1
    fi
fi
printf 'Firmware version %s; firmware changed since the merge base with %s: %s.\n' "$current" "$base_ref" "$changed"
