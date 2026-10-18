#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
select_xcode
bash "$root/Scripts/bootstrap-firmware.sh"

cmake -S "$root/Firmware" -B "$root/.build/firmware" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DPICO_SDK_PATH="$root/.tools/pico-sdk" \
    -DPICO_TOOLCHAIN_PATH="$root/.tools/arm" \
    -DPICOTOOL_FORCE_FETCH_FROM_GIT=ON \
    -DPICOTOOL_FETCH_FROM_GIT_PATH="$root/.tools/picotool"
cmake --build "$root/.build/firmware" --parallel
"$root/.tools/arm/bin/arm-none-eabi-size" "$root/.build/firmware/nxs_firmware.elf"
"$root/.tools/picotool/picotool/picotool" info -a "$root/.build/firmware/nxs_firmware.uf2"
