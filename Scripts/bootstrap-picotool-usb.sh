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
# -DPICOTOOL_NO_LIBUSB=1, for `picotool info -a` on a UF2 only), this checkout links Homebrew's
# static libusb, the same library NXSUSBHostShim links, so the app can reboot a board into
# BOOTSEL, flash it, and verify it without a system picotool or a libusb outside its bundle.
# picotool's FindLIBUSB.cmake takes both values from the cache instead of asking pkg-config.
build="$root/.build/picotool-usb"
libusb="/opt/homebrew/opt/libusb"
cmake -S "$src" -B "$build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DPICO_SDK_PATH="$root/.tools/pico-sdk" \
    -DCMAKE_PREFIX_PATH=/opt/homebrew \
    -DLIBUSB_INCLUDE_DIR="$libusb/include/libusb-1.0" \
    "-DLIBUSB_LIBRARIES=$libusb/lib/libusb-1.0.a;-lobjc;-Wl,-framework,IOKit;-Wl,-framework,CoreFoundation;-Wl,-framework,Security"
cmake --build "$build" --target picotool --parallel

binary="$build/picotool"
if [ ! -x "$binary" ]; then
    printf 'picotool build did not produce %s\n' "$binary" >&2
    exit 1
fi
# grep reads all of nm's output: with -q it would stop at the first match, nm would fail on the
# closed pipe, and pipefail would report the linked-in library as missing.
if ! nm "$binary" | grep ' T _libusb_init$' >/dev/null; then
    printf 'Embedded picotool was built without libusb; refusing a USB-incapable binary.\n' >&2
    exit 1
fi
bash "$root/Scripts/check-system-libraries.sh" "$binary"
# Signed as code of its own, so the app's seal covers a valid executable rather than an unsigned one.
codesign --force --sign - "$binary"

destination="$root/App/Workbench/Sources/NeXTsoundWorkbench/Resources/picotool"
cp "$binary" "$destination"
chmod +x "$destination"
printf 'picotool %s with USB support ready at %s\n' "$commit" "$destination"
