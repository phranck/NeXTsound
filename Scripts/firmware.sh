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
bounds_dir=$(mktemp -d "$root/.build/flash-bounds.XXXXXX")
trap 'rm -r "$bounds_dir"' EXIT
bounds_arguments=(--relocatable --defsym=__flash_binary_start=0x10000000
    "--script=$root/.build/firmware/storage_bounds.ld"
    "$root/.build/firmware/Core/CMakeFiles/nxs_storage.dir/flash_geometry.c.o")
"$root/.tools/arm/bin/arm-none-eabi-ld" "${bounds_arguments[@]}" --defsym=__flash_binary_end=0x103fe000 -o "$bounds_dir/accepted.elf"
if "$root/.tools/arm/bin/arm-none-eabi-ld" "${bounds_arguments[@]}" --defsym=__flash_binary_end=0x103fe001 \
    -o "$bounds_dir/rejected.elf" >"$bounds_dir/rejected.log" 2>&1; then
    printf 'Storage linker guard accepted an overlapping image\n' >&2
    exit 1
fi
grep -Fq 'NeXTsound firmware overlaps persistent snapshot sectors' "$bounds_dir/rejected.log"
printf 'Storage linker guard accepts the boundary and rejects a one-byte overlap.\n'
"$root/.tools/arm/bin/arm-none-eabi-size" "$root/.build/firmware/nxs_firmware.elf"
"$root/.tools/picotool/picotool/picotool" info -a "$root/.build/firmware/nxs_firmware.uf2"
