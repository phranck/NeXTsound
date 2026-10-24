# Shared control codec

`Shared` contains the portable C wire codec and the Swift sound-profile model. The C codec owns packet sizes, byte encoding, and DSP parameter limits. The Swift API uses that codec rather than implementing another binary serializer.

## Validation

Run the complete shared-package checks from the repository root:

```bash
bash Scripts/check.sh
```

The script selects the Xcode build pinned in `toolchain.json`, installs the checksum-pinned local format/lint tools, checks source formatting and its regression fixtures, runs C host tests with address/undefined-behavior sanitizers, runs Swift tests, and builds the package in Release mode. It also cross-builds the [RP2350 firmware and DSP probe](Firmware.md) using pinned project-local firmware tools, then checks the compiled USB descriptors and generated PIO instructions on the host. It does not access a USB device.

## Wire data

The canonical declarations are in [`nxs_protocol.h`](../Shared/Sources/NeXTsoundProtocol/include/nxs_protocol.h). [`protocol.c`](../Shared/Sources/NeXTsoundProtocol/protocol.c) implements the explicit little-endian encoders and decoders. Native C structs, their padding, and Swift memory layouts are not wire formats.

`NXS_REPORT_SIZE` includes the HID report-ID byte. The envelope identifies the protocol version, operation, request, result, and state generation. Request IDs are nonzero. Requests cannot contain a response result. Unused bytes are zero, and a decoder rejects nonzero padding, unsupported versions, invalid lengths, and unknown operations.

The operation numbers are wire values that installed firmware and apps exchange, so they never change.

| Value | Operation | Request payload | Reply payload |
| --- | --- | --- | --- |
| 1 | `NXS_OPERATION_CAPABILITIES` | none | 136-byte capabilities |
| 2 | `NXS_OPERATION_READ_STATE` | none | 120-byte active snapshot |
| 3 | `NXS_OPERATION_APPLY_STATE` | 120-byte snapshot | none, after the audio owner accepts it |
| 4 | `NXS_OPERATION_PERSIST_STATE` | none | none, after the active snapshot is saved |
| 5 | `NXS_OPERATION_STATUS` | none | 40-byte runtime status |
| 6 | `NXS_OPERATION_SET_NAME` | 32-byte device name | none, after the name is saved |
| 7 | `NXS_OPERATION_DIAGNOSTICS` | none | 32-byte diagnostics, protocol minor 1 only |
| 8 | `NXS_OPERATION_READ_METADATA` | 1-byte part index | 164-byte part of the owner metadata, protocol minor 1 only |
| 9 | `NXS_OPERATION_WRITE_METADATA` | 168 bytes: part index, three zero bytes, part | none; part 1 replies after the save, protocol minor 1 only |

DSP values use IEEE-754 binary32 in physical units. All settings, including disabled filters, must contain finite values inside the canonical bounds returned by `nxs_parameter_range`. Snapshot, capability, runtime-status, and diagnostic payloads have dedicated codecs and exported size constants. A failed C decode leaves its destination unchanged.

The [golden capability-request fixture](../Shared/Tests/NeXTsoundCoreTests/Fixtures/capabilities-request.hex) is consumed by both the C and Swift test suites. It fixes byte order independently of the encoder implementation. Fixture identifiers and capability values are test data, not readings from a board.

Capability text is bounded ASCII. Populate the device serial and firmware version before encoding a default capability object. The device name is printable ASCII, spaces included, with at most 31 characters. It is empty while no custom name is stored, and the USB product string then keeps its default. Setting a name requires storage and advances the generation once it is saved. Persistence requires the verified-flash feature flag and a nonzero reported capacity. Validating those fields does not establish a physical flash measurement.

## Runtime diagnostics and compatible revisions

Protocol 1.1 adds the read-only `NXS_OPERATION_DIAGNOSTICS` operation and, from firmware 0.2.0, the two metadata operations. The message's `protocol_minor` selects its envelope revision. The firmware accepts minor 0 or 1 and echoes the request revision in every reply, including deferred replies. Diagnostics and metadata require minor 1. For minor-0 capability requests, the firmware omits `NXS_FEATURE_DIAGNOSTICS` and `NXS_FEATURE_METADATA` so existing 1.0 clients retain their known capability flags. Minor-1 clients discover support through those flags. A client communicating with older 1.0 firmware can explicitly select minor 0.

Capability decoders drop feature bits they do not know rather than refusing the reply, so a later firmware never locks out an app that predates one of its features. Encoders still refuse unknown bits. Apps before firmware 0.2.0 refuse `NXS_FEATURE_METADATA` because they predate this rule, so they cannot verify a board running 0.2.0; the app bundles the firmware it matches.

The 120-byte active snapshot and 40-byte runtime status keep their existing layouts. Persistent records use `NXS_SNAPSHOT_PROTOCOL_MAJOR` and `NXS_SNAPSHOT_PROTOCOL_MINOR`, which remain 1.0 independently of the envelope revision.

The diagnostic payload is 32 bytes. All integers are little-endian.

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 2 | Diagnostic schema version, 1 |
| 2 | 2 | Payload size, 32 |
| 4 | 4 | Post-prime audio-ring underruns |
| 8 | 4 | Detected I2S PIO TX stalls |
| 12 | 4 | Rejected audio packets, including maintenance drops |
| 16 | 4 | DSP processing failures |
| 20 | 4 | Instrumented processing-deadline misses |
| 24 | 4 | TinyUSB suspend callback notifications |
| 28 | 4 | TinyUSB resume callback notifications |

Counters are boot-session unsigned values and wrap modulo 2^32. Ring underruns plus I2S stalls produce the existing aggregate underrun count. Rejected packets, DSP failures, and deadline misses produce its aggregate overrun count. The audio owner samples these counters and status in one queue item; the USB owner adds its callback counts. Separate requests can observe different blocks. An exact duplicate request replays its original sample, so use a new request ID for fresh counters.

The operation accepts no request payload and changes no snapshot, generation, or stored record. The callback counts record firmware notifications, not an electrical measurement of USB suspend current.

## Owner metadata

The owner metadata of [issue 39](https://github.com/phranck/NeXTsound/issues/39) is a 328-byte block, larger than one report, so it travels in two 164-byte parts. `nxs_owner_metadata_encode` and `nxs_owner_metadata_decode` own the block, and the firmware and the app validate it with the same `nxs_owner_metadata_is_valid`. Integers are little-endian. Zero means unset in every field except the serial number, whose flag tells 0, which the app shows as NXSB0000, from no number.

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 4 | The owner's date as YYYYMMDD, a valid Gregorian date from year 1 to 9999 |
| 4 | 3 | Serial number, which the app shows after the prefix `NXSB` |
| 7 | 1 | Flags: bit 0 `NXS_METADATA_FLAG_SERIAL_NUMBER` when a serial number is set, the other bits 0. Without the flag, a serial number of 0 means none and any other is set, as firmware 0.2.0 sent it |
| 8 | 64 | Owner, UTF-8 without control characters, padded with zero bytes |
| 72 | 256 | Note, UTF-8 whose only control character is the line feed, padded with zero bytes |

A text may fill its whole field without a terminator, and every byte after the text must be zero. `NXS_OPERATION_READ_METADATA` returns one part of the current block; a client reads both and checks that both replies carry the same generation. `NXS_OPERATION_WRITE_METADATA` requires storage and the current generation. Part 0 is held for its USB session and generation and replies at once. Part 1 completes the block, which the firmware validates and saves like a name, and its reply follows the save with the next generation. A part 1 without a held part 0 from the same session and generation is refused, so a half-written update changes nothing. Saving a profile or a name writes the current metadata back unchanged.

## Swift API

[`WireCodec`](../Shared/Sources/NeXTsoundCore/WireCodec.swift) bridges messages, DSP snapshots, capabilities, runtime status, diagnostics, and owner metadata to the C implementation. New Swift messages default to minor 1; their `protocolMinor` can select minor 0. `WireMessage.validateResponse(to:)` checks response direction, request identity, operation identity, envelope revision, and the result code. USB transport completion alone is not an acknowledgement.

The library encodes and validates data. [`Firmware/Core/device.c`](../Firmware/Core/device.c) implements capabilities, state, apply, persistence, status, naming, diagnostics, and owner-metadata execution. [`Firmware/USB/control.c`](../Firmware/USB/control.c) bridges TinyUSB to the codec. Apply succeeds only after audio-owner acceptance; transport completion does not advance the state generation. [Persistent storage](Storage.md) is available only after its geometry and execution gates pass.

TinyUSB removes the matching report-ID byte before the SET_REPORT callback and prefixes it around GET_REPORT. These callbacks handle 255 data bytes; the canonical codec and host transport handle all 256 bytes. A client must match the response operation and request ID rather than interpreting the previous reply as acknowledgement of a pending apply. Requests should be serialized.

The control owner caches four completed request/reply pairs. An exact duplicate replays its original response. Reusing a cached ID with different contents is rejected. Retrying a completed failure, such as busy, requires a new request ID. Generation preconditions prevent an evicted successful apply from executing again. USB configuration and disconnect reset the session cache without discarding an already accepted in-flight apply. Request IDs belong to their connected session. An old session's pending apply neither reserves its ID in the new session nor publishes its old reply there.

## Sound profiles

[`SoundProfile`](../Shared/Sources/NeXTsoundCore/SoundProfile.swift) is a versioned JSON document. Both direct Codable encoding/decoding and the convenience methods validate the profile. Unknown format versions are rejected before their contents are interpreted.

A profile contains its DSP settings and value snapshots of speaker/enclosure records. Unknown specifications and volume estimates stay absent. Net air volume is derived from internal volume minus component displacement rather than stored a second time. Model-derived volume requires a model reference; optional SHA-256 digests must be valid hexadecimal digests.

Factory presets are muted listening starting points. They do not supply speaker specifications, an acoustic calibration, or a verified speaker-protection limit.
