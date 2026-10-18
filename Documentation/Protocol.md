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

DSP values use IEEE-754 binary32 in physical units. All settings, including disabled filters, must contain finite values inside the canonical bounds returned by `nxs_parameter_range`. Snapshot, capability, and runtime-status payloads have dedicated codecs and exported size constants. A failed C decode leaves its destination unchanged.

The [golden capability-request fixture](../Shared/Tests/NeXTsoundCoreTests/Fixtures/capabilities-request.hex) is consumed by both the C and Swift test suites. It fixes byte order independently of the encoder implementation. Fixture identifiers and capability values are test data, not readings from a board.

Capability text is bounded ASCII. Populate the device serial and firmware version before encoding a default capability object. Persistence requires the verified-flash feature flag and a nonzero reported capacity. Validating those fields does not establish a physical flash measurement.

## Swift API

[`WireCodec`](../Shared/Sources/NeXTsoundCore/WireCodec.swift) bridges messages, DSP snapshots, capabilities, and runtime status to the C implementation. `WireMessage.validateResponse(to:)` checks response direction, request identity, operation identity, and the result code. USB transport completion alone is not an acknowledgement.

The library encodes and validates data. [`Firmware/Core/device.c`](../Firmware/Core/device.c) implements capabilities, state, apply, and status execution. [`Firmware/USB/control.c`](../Firmware/USB/control.c) bridges TinyUSB to the codec. Apply succeeds only after audio-owner acceptance; transport completion does not advance the state generation. Persistent storage remains unavailable.

TinyUSB removes the matching report-ID byte before the SET_REPORT callback and prefixes it around GET_REPORT. These callbacks handle 255 data bytes; the canonical codec and host transport handle all 256 bytes. A client must match the response operation and request ID rather than interpreting the previous reply as acknowledgement of a pending apply. Requests should be serialized.

The control owner caches four completed request/reply pairs. An exact duplicate replays its original response. Reusing a cached ID with different contents is rejected. Retrying a completed failure, such as busy, requires a new request ID. Generation preconditions prevent an evicted successful apply from executing again. USB configuration and disconnect reset the session cache without discarding an already accepted in-flight apply. Request IDs belong to their connected session. An old session's pending apply neither reserves its ID in the new session nor publishes its old reply there.

## Sound profiles

[`SoundProfile`](../Shared/Sources/NeXTsoundCore/SoundProfile.swift) is a versioned JSON document. Both direct Codable encoding/decoding and the convenience methods validate the profile. Unknown format versions are rejected before their contents are interpreted.

A profile contains its DSP settings and value snapshots of speaker/enclosure records. Unknown specifications and volume estimates stay absent. Net air volume is derived from internal volume minus component displacement rather than stored a second time. Model-derived volume requires a model reference; optional SHA-256 digests must be valid hexadecimal digests.

Factory presets are muted listening starting points. They do not supply speaker specifications, an acoustic calibration, or a verified speaker-protection limit.
