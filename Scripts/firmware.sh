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
python3 "$root/Scripts/check-ram-elf.py" "$root/.tools/arm/bin/arm-none-eabi-readelf" "$root/.build/firmware/nxs_flash_probe.elf"
if python3 "$root/Scripts/check-ram-elf.py" "$root/.tools/arm/bin/arm-none-eabi-readelf" "$root/.build/firmware/nxs_firmware.elf" >/dev/null 2>&1; then
    printf 'SRAM guard accepted the flash-linked negative control\n' >&2
    exit 1
fi
printf 'SRAM guard rejects the flash-linked negative control.\n'
"$root/.tools/arm/bin/arm-none-eabi-size" "$root/.build/firmware/nxs_firmware.elf"
"$root/.tools/picotool/picotool/picotool" info -a "$root/.build/firmware/nxs_firmware.uf2"
