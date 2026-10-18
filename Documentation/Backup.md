# Flash identification and recovery

Preserve the intended board's entire physical flash before replacing its firmware. Raw captures and specimen-specific restore instructions belong in the ignored `.backups` directory, not Git. Retain the original firmware and filesystem together.

## Identify the specimen and capacity

Use the USB-enabled `picotool` 2.3.1 for hardware operations. The project-local build-time picotool has no USB support. Filter every device operation by the observed VID, PID, and unique serial. A firmware build description does not identify the physical PCB.

`picotool info -d` reports a flash-size estimate based on mapped-address aliases. Its [implementation](https://github.com/raspberrypi/picotool/blob/2041936441b48a3cc53ae3da9e805229fe8f4e18/main.cpp#L3176-L3196) does not read JEDEC/SFDP geometry. Preserve that range first, then independently read chip metadata before declaring the backup complete.

[`nxs_flash_probe`](../Firmware/Probes/flash_probe.c) is a separate RP2350 RAM-only target. It reads only JEDEC `0x9f` and SFDP `0x5a`, then reports their bytes and chip serial over the SDK's USB CDC interface. It has no audio interface or GPIO audio setup. The SDK excludes `flash_do_cmd` from `PICO_NO_FLASH` builds, so the probe adapts its QMI read loop and starts generic XIP through `flash_start_xip`. It does not issue erase, program, write-enable, OTP, or security-setting commands.

`bash Scripts/firmware.sh` builds the probe and runs [`check-ram-elf.py`](../Scripts/check-ram-elf.py). The check requires every ELF load segment, its memory extent, and its loaded entry point to lie within RP2350 SRAM. Inspect and retain the ELF, segment report, source/image hashes, and exact target filters before loading it. Load the ELF directly into RAM; a raw BIN defaults to flash address `0x10000000`.

## Observed specimen

On October 18, 2026, the intended specimen reported ROM chip ID/USB serial `D4CDD489AFE28CC5`, RP2350/QFN60. The RAM probe returned JEDEC `852016`, SFDP 1.0, a nine-DWORD basic table, 33554432 density bits, and 4096-byte sector erase with opcode `0x20`. Thus its physical flash capacity is 4194304 bytes. The probe reported a 150000000 Hz system clock through the SDK clock API.

The JEDEC tuple matches the [PY25Q32HB manufacturer's identification table](https://www.puyasemi.com/download_path/%E6%95%B0%E6%8D%AE%E6%89%8B%E5%86%8C/Flash%20%E8%8A%AF%E7%89%87/PY25Q32HB_Datasheet_V1.7.pdf#page=67). Its [Page Program specification](https://www.puyasemi.com/download_path/%E6%95%B0%E6%8D%AE%E6%89%8B%E5%86%8C/Flash%20%E8%8A%AF%E7%89%87/PY25Q32HB_Datasheet_V1.7.pdf#page=55) defines 256-byte pages and aligned full-page writes. The observed basic SFDP revision does not contain the later page-size DWORD. Page size therefore comes from the matching manufacturer's specification, not a measured program operation. Package markings and the physical PCB model remain unverified by these software observations.

The original MicroPython v1.29.0 image uses a `pico2` firmware target and SDK 2.3.0. Its embedded filesystem spans `0x10100000` through `0x10400000`. This describes the saved image, not the physical board model.

## Capture and verify

Create a private unique directory with `umask 077` and preserve the identity/geometry evidence there. In BOOTSEL, this specimen is `2e8a:000f`. Read the entire confirmed range twice into separate files using the same exact device filters:

```bash
picotool save -r 0x10000000 0x10400000 "$BACKUP/mapped-flash-a.bin" -t bin \
  --vid 0x2e8a --pid 0x000f --ser D4CDD489AFE28CC5
picotool save -r 0x10000000 0x10400000 "$BACKUP/mapped-flash-b.bin" -t bin \
  --vid 0x2e8a --pid 0x000f --ser D4CDD489AFE28CC5
cmp "$BACKUP/mapped-flash-a.bin" "$BACKUP/mapped-flash-b.bin"
shasum -a 256 "$BACKUP/mapped-flash-a.bin" "$BACKUP/mapped-flash-b.bin"
```

Both observed 4194304-byte captures have SHA-256 `d0edc9763780aee891a36a572759da4883b03f2f34cadd31a5564d5711270414`. A third full read after the RAM probe matches them byte for byte. The original flash contents are unchanged. The backup includes the filesystem; do not inspect or publish its user data as test fixtures.

## Retain a restoration path

Store target-specific `RESTORE.md` instructions beside the images and a manifest recording their range, byte count, hashes, chip ID, metadata source, and verification results. Before restoration, reconfirm the exact specimen, file size, and hash. Restore the full raw image to explicit offset `0x10000000` with `picotool load --ignore-partitions -v`, using the same device filters. Read the complete range back and compare it before rebooting. Do not change protection, OTP, or security settings to bypass an error.

For this specimen, restoration is documented but not exercised. The board remains in BOOTSEL; no NeXTsound image is installed in flash. Persistence stays unavailable until the storage implementation and coordinated flash-write path are complete. A verified backup does not qualify amplifier wiring, I2S signals, runtime headroom, or speaker safety.
