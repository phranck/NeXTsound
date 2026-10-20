#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
bash "$root/Scripts/bootstrap-firmware.sh"

src="$root/.tools/picotool-usb"
commit=$(jq -r '.firmware.picotool.commit' "$manifest")
if [ ! -d "$src/.git" ]; then
    git init -q "$src"
    git -C "$src" remote add origin https://github.com/raspberrypi/picotool.git
fi
if [ "$(git -C "$src" rev-parse --verify HEAD 2>/dev/null || true)" != "$commit" ]; then
    if [ -n "$(git -C "$src" status --porcelain)" ]; then
        printf 'Refusing to replace a modified picotool checkout.\n' >&2
        exit 1
    fi
    git -C "$src" fetch --depth 1 origin "$commit"
    git -C "$src" checkout --detach FETCH_HEAD
fi

# Unlike the project-local .tools/picotool (built by the Pico SDK's own glue with
# -DPICOTOOL_NO_LIBUSB=1, for `picotool info -a` on a UF2 only), this checkout is built
# directly against Homebrew's libusb, the same library NXSUSBHostShim already links, so the
# app can reboot a board into BOOTSEL, flash it, and verify it without a system picotool.
build="$root/.build/picotool-usb"
PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
    cmake -S "$src" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DPICO_SDK_PATH="$root/.tools/pico-sdk" \
    -DCMAKE_PREFIX_PATH=/opt/homebrew
cmake --build "$build" --target picotool --parallel

binary="$build/picotool"
if [ ! -x "$binary" ]; then
    printf 'picotool build did not produce %s\n' "$binary" >&2
    exit 1
fi
if ! otool -L "$binary" | grep -q 'libusb-1\.0'; then
    printf 'Embedded picotool was built without libusb; refusing a USB-incapable binary.\n' >&2
    exit 1
fi

destination="$root/App/Workbench/Sources/NeXTsoundWorkbench/Resources/picotool"
cp "$binary" "$destination"
chmod +x "$destination"
printf 'picotool %s with USB support ready at %s\n' "$commit" "$destination"
