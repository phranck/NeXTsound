# Recoverable snapshot storage

The portable [`nxs_storage`](../Firmware/Core/include/nxs_storage.h) library validates, selects, and replaces saved snapshots. It uses the canonical protocol's snapshot codec. It does not serialize native structs or transport request IDs.

The firmware connects this core to deferred device persistence through geometry-gated platform callbacks. Host integration tests and the RP2350 cross-build cover this connection. Muted build `7a033203` was installed on specimen `D4CDD489AFE28CC5` on October 18, 2026. Targeted HID, persistence, reboot, and controlled corruption checks passed. See the [structured device observations](Verification/Storage-2026-10-18.json).

## Layout

There are two isolated 4096-byte sectors. A record occupies the first 768 bytes of a sector: the data page, the commit page, and the note page, in that order. Each 256-byte page is programmed once after erase. The remaining sector bytes are unused by this format.

All integers are little-endian. Every save writes storage format 2, which adds the owner metadata of [issue 39](https://github.com/phranck/NeXTsound/issues/39). Format 1 records, as firmware before 0.1.1 writes them, still decode with empty metadata, provided their note page is erased. Firmware before 0.1.1 does not read format 2, so it falls back to a format-1 record in the other sector if there is one. Both formats embed protocol snapshot version 1.0 through `NXS_SNAPSHOT_PROTOCOL_MAJOR` and `NXS_SNAPSHOT_PROTOCOL_MINOR`. This version does not advance when the HID envelope adds operations. Unknown versions, generation zero, invalid snapshots, metadata that [`nxs_owner_metadata_is_valid`](Protocol.md#owner-metadata) refuses, and dirty padding are rejected.

| Data-page offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 4 | `NXSP` magic |
| 4 | 2 | Storage format version, 1 or 2 |
| 6 | 2 | Data-page size, 256 |
| 8 | 4 | Snapshot generation |
| 12 | 1 | Protocol major version |
| 13 | 1 | Protocol minor version |
| 14 | 2 | Snapshot payload size, 120 |
| 16 | 120 | Canonical `nxs_snapshot_encode` payload |
| 136 | 32 | Device name, zero-padded |
| 168 | 4 | Format 2: the owner's date as YYYYMMDD, 0 when unset |
| 172 | 3 | Format 2: serial number, 0 when unset |
| 175 | 1 | Format 2: flags, bit 0 `NXS_METADATA_FLAG_SERIAL_NUMBER` when a serial number is set; firmware 0.2.0 wrote 0 here and refuses any other value |
| 176 | 64 | Format 2: owner, UTF-8 padded with zero bytes |
| 240 | 12 | Erased padding, `0xff`; in format 1 the padding starts at 168 |
| 252 | 4 | CRC-32/ISO-HDLC of data-page bytes 0 through 251, continued over the whole note page in format 2 |

The commit page starts at record offset 256. Its offsets below are relative to that page.

| Commit-page offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 4 | `NXSC` magic |
| 4 | 4 | Matching snapshot generation |
| 8 | 4 | Matching record CRC |
| 12 | 4 | Bitwise complement of that CRC |
| 16 | 240 | Erased padding, `0xff` |

The note page starts at record offset 512 and holds the owner's 256-byte note, UTF-8 padded with zero bytes. Format 1 leaves it erased. It follows the commit page in the record so that format-1 records keep their layout.

The commit page is written last, after the data and note pages have passed readback comparison. CRC detects accidental corruption; it is not authentication.

## Selection and generations

`nxs_storage_read` reads both records before choosing the largest valid unsigned generation. A corrupted record can fall back to the other valid record. Two identical records with the same generation are equivalent. Different valid records with the same generation are ambiguous and prevent automatic replacement.

An I/O read failure prevents selection and saving because the unread slot might contain the only valid record. Empty, failed, and ambiguous reads leave caller destinations unchanged. The caller retains its muted factory configuration when no saved state can be loaded.

`nxs_storage_save` scans the media anew on every call. This matters if the newest record became corrupt after an earlier load. The surviving valid record must remain intact while the other sector is replaced. Lower generations and same-generation changes return `NXS_RESULT_STALE_GENERATION`. An identical same-generation save verifies the existing record and performs no erase or program operation. Generations do not wrap.

## Write and acknowledgement

The I/O callbacks address only a slot and one of its three pages. The platform must map them into verified flash bounds and arrange safe execution. The storage core keeps its records in static buffers, because two records and their decoded states would not fit the 4 KiB stack of the control core; it runs only there and never reentrantly.

1. Scan both slots and validate the requested generation, snapshot, and serial number.
2. Erase the inactive sector and verify that its record space is erased.
3. Program the data page and compare its readback. The note and commit pages must remain erased.
4. Program the note page and compare its readback. The commit page must remain erased.
5. Program the commit page and compare the complete record with the expected one.
6. Decode the record, and return success only after that verification.

Because the device holds the metadata restored at boot and puts it into every save, saving a profile or a name keeps the owner metadata.

A failed final read can leave a complete new record even though no success was acknowledged. A later boot or rescan can select it. Clients must read device state after an uncertain save rather than infer that the older record is still current.

## Geometry and execution gates

[`nxs_flash_geometry_decode`](../Firmware/Core/flash_geometry.c) accepts only the observed `85 20 16` JEDEC ID, compatible SFDP 1.0 metadata, a 4 MiB density, and a 4096-byte `20h` erase type. The matching [PY25Q32HB V1.7 datasheet](https://www.puyasemi.com/download_path/%E6%95%B0%E6%8D%AE%E6%89%8B%E5%86%8C/Flash%20%E8%8A%AF%E7%89%87/PY25Q32HB_Datasheet_V1.7.pdf) supplies the 256-byte page qualification. Unknown or malformed metadata disables writes. See [specimen identification and backup](Backup.md).

A shared macro-only [layout header](../Firmware/Core/include/nxs_storage_layout.h) reserves sectors at offsets `0x3fe000` and `0x3ff000`. A linker assertion rejects firmware overlap, and the runtime geometry check independently rejects it. The build tests both an image ending exactly at the boundary and a one-byte overlap. The flash-linked targets select the SDK's read-only `boot2_generic_03h` setup rather than a setup that can write status registers. Its divider of four gives a calculated 37.5 MHz SPI read clock at 150 MHz, below the manufacturer's 55 MHz READ limit. This is not a runtime-headroom measurement.

Before launching core 1 or initializing USB, core 0 reads JEDEC/SFDP metadata and scans the two records. A valid saved record initializes both the audio owner and the device generation. Otherwise the factory snapshot remains muted. Ambiguous records and I/O failures disable persistence. Capabilities and `storage_available` are enabled only when geometry, load status, and the SDK multicore flash-safety setup permit writes.

A persistence request captures the active snapshot and generation. Its reply is deferred. The audio owner drains its final-output envelope, stops DMA/PIO, and acknowledges the current maintenance token. Fresh tokens prevent stale pause acknowledgements from authorizing another operation. The control core then invokes `flash_safe_execute`; its SDK multicore lockout parks core 1 and disables core 0 interrupts during each erase/program callback. Neither core-safe assumption is enabled. Flash-safe errors disable further writes for that boot.

No TinyUSB work occurs inside the flash-disabled callback. The producer remains gated through the next `tud_task` pass after saving, queued audio is discarded, and a new stream epoch forces re-priming before output resumes. Device acknowledgement follows complete record readback. Audio telemetry updates preserve control-owned storage fields. Accepted persistence survives a USB session reset, but its old request ID/reply does not enter the new session.

The SDK/picotool-compatible reset interface also requests audio maintenance. Reset is performed from the main loop only after quiescence, never from a USB callback. BOOTSEL requests retain PICOBOOT access and do not configure an activity GPIO.

## Device verification

The intended specimen booted with generation 1, profile mute enabled, attenuation at -24 dB, and no persisted generation. HID reported the matching serial, firmware revision, 4 MiB geometry, and both storage feature flags. Applying and saving a muted -18 dB configuration produced generation 2, which survived the SDK-compatible watchdog reboot. Exact apply/save retries replayed their replies; a stale-generation save was rejected.

A second save produced a valid generation 3 record in the other sector. BOOTSEL readback and the canonical host storage decoder verified both records. A controlled BOOTSEL write changed one stored-CRC bit in the owned newest test sector only. The firmware then loaded generation 2. Saving again repaired the inactive sector with a new valid generation 3 at -24 dB. Complete sector readback confirmed that the surviving older sector remained byte-identical. The final reboot restored the new generation 3 with mute still enabled.

Both BOOTSEL and flash reboot paths were exercised. A controlled BOOTSEL/runtime re-enumeration retained the stable `BuiltInHeadphoneOutputDevice` UID for both system output roles; numeric handles alone were not a sufficient comparison. The harness never selected a system output or disabled profile mute.

These were control/storage tests without a USB audio stream. They do not establish full-load audio headroom, electrical I2S behavior, suspend current, runtime stack high-water use, or physical power-loss recovery. The injected corrupt record was written by the bootloader, not produced by interrupting a firmware write. Original-firmware restoration remains documented but unexercised.

## Host verification

[`storage_tests.c`](../Firmware/Tests/storage_tests.c) uses fresh in-memory sectors. Its NOR model programs bits only from one to zero. Tests cover every byte-prefix cutoff across all three program pages and a sector erase, every individual record-bit corruption, CRC-valid malformed headers/snapshots, I/O failures, conflicting generations, and a newest record corrupted before the next save. The [format-1 fixture](../Firmware/Tests/Fixtures/storage-record-v1.hex) is the record that the format-1 encoder of firmware 0.1.0 writes; it must decode to the same snapshot, generation, and name, reject every single-bit change, and be replaced by a format-2 record in the other sector on the next save.

The host tests compare CRCs with zlib from the pinned Xcode SDK. Removing the data-CRC check or commit-magic check separately causes the corruption test to fail, and so does removing format-1 decoding. With all of them present, 117718 assertions pass. These are software-model results, not physical power-loss tests or flash-execution timing measurements. Geometry tests use only captured SFDP metadata, not original user flash. USB callback fixtures cover deferred saves, producer gating, post-flash draining, telemetry ownership, exact retries, and session-reset completion. The reset-driver fixture checks request type, interface, values, stages, and bus-reset cancellation. Removing telemetry-field ownership makes the actual callback regression fail.
