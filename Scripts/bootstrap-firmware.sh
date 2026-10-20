#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

expected_host=$(jq -r '.firmware.arm.host' "$manifest")
actual_host="$(uname -s)-$(uname -m)"
if [ "$actual_host" != "$expected_host" ]; then
    printf 'Firmware tools require %s; this host is %s.\n' "$expected_host" "$actual_host" >&2
    exit 1
fi

version=$(jq -r '.firmware.arm.version' "$manifest")
compiler="$root/.tools/arm/bin/arm-none-eabi-gcc"
if [ ! -x "$compiler" ] || [ "$("$compiler" -dumpfullversion)" != "$version" ]; then
    temporary=$(mktemp -d "${TMPDIR:-/tmp}/NeXTsound-arm.XXXXXX")
    trap 'command rm -rf "$temporary"' EXIT
    url=$(jq -r '.firmware.arm.url' "$manifest")
    checksum=$(jq -r '.firmware.arm.sha256' "$manifest")
    curl --fail --location --silent --show-error --retry 3 "$url" --output "$temporary/arm.tar.xz"
    printf '%s  %s\n' "$checksum" "$temporary/arm.tar.xz" | shasum -a 256 -c -
    mkdir -p "$root/.tools/arm"
    tar -xf "$temporary/arm.tar.xz" -C "$root/.tools/arm" --strip-components=1
fi
if [ "$("$compiler" -dumpfullversion)" != "$version" ]; then
    printf 'Arm compiler version does not match toolchain.json.\n' >&2
    exit 1
fi

sdk="$root/.tools/pico-sdk"
commit=$(jq -r '.firmware.pico_sdk.commit' "$manifest")
if [ ! -d "$sdk/.git" ]; then
    url=$(jq -r '.firmware.pico_sdk.url' "$manifest")
    git init -q "$sdk"
    git -C "$sdk" remote add origin "$url"
fi
if [ "$(git -C "$sdk" rev-parse --verify HEAD 2>/dev/null || true)" != "$commit" ]; then
    if [ -n "$(git -C "$sdk" status --porcelain)" ]; then
        printf 'Refusing to replace a modified Pico SDK checkout.\n' >&2
        exit 1
    fi
    git -C "$sdk" fetch --depth 1 origin "$commit"
    git -C "$sdk" checkout --detach FETCH_HEAD
fi
git -C "$sdk" submodule update --init --depth 1 lib/tinyusb
tinyusb=$(jq -r '.firmware.pico_sdk.tinyusb_commit' "$manifest")
if [ "$(git -C "$sdk/lib/tinyusb" rev-parse HEAD)" != "$tinyusb" ]; then
    # Pico SDK's own lib/tinyusb pin has not moved across any of its releases through 2.3.1
    # (still 86ad6e56, Dec 2024), so a newer TinyUSB is checked out directly from its own
    # upstream remote (which the submodule already points at) instead of waiting on a Pico SDK
    # release to carry it.
    if [ -n "$(git -C "$sdk/lib/tinyusb" status --porcelain)" ]; then
        printf 'Refusing to replace a modified TinyUSB checkout.\n' >&2
        exit 1
    fi
    git -C "$sdk/lib/tinyusb" fetch --depth 1 origin "$tinyusb"
    git -C "$sdk/lib/tinyusb" checkout --detach FETCH_HEAD
fi
if [ "$(git -C "$sdk/lib/tinyusb" rev-parse HEAD)" != "$tinyusb" ]; then
    printf 'TinyUSB does not match toolchain.json.\n' >&2
    exit 1
fi
# lib/tinyusb deliberately shows as a modified submodule reference in the Pico SDK
# superproject's own status whenever its pinned commit here differs from Pico SDK's own
# (expected above); only other modifications are refused.
sdk_dirty=$(git -C "$sdk" status --porcelain --untracked-files=no | grep -v ' lib/tinyusb$' || true)
if [ -n "$sdk_dirty" ] || \
    [ -n "$(git -C "$sdk/lib/tinyusb" status --porcelain --untracked-files=no)" ]; then
    printf 'Pico SDK or TinyUSB contains modified tracked files.\n' >&2
    exit 1
fi
printf 'Arm %s and Pico SDK %s ready.\n' "$version" "$commit"
