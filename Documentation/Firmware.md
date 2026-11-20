# Development firmware

The RP2350 target integrates 48 kHz stereo UAC2 playback, vendor-defined HID control, and mono I2S output. Its entry point is [`Firmware/main.c`](../Firmware/main.c). This is a private bench build, not a hardware-qualified release.

## Build

```bash
bash Scripts/firmware.sh
```

The script bootstraps the pinned project-local tools, builds all three firmware targets, tests the persistent-sector linker boundary, and inspects `nxs_firmware.uf2` as a file. It does not access a connected board or install firmware. Outputs are in `.build/firmware`. The separate `nxs_dsp_probe` target configures no USB or audio output. The SRAM-only `nxs_flash_probe` reads chip metadata over USB CDC; its ELF load ranges are checked during the build. See [flash identification and recovery](Backup.md).

`toolchain.json` supplies the board and dependency revisions. The audio firmware reserves 4 KiB stacks for both cores in the SDK's scratch banks. GCC emits `.su` frame reports beside its objects. These reports are not a measurement of interrupt-inclusive stack high-water use.

## Status LED

The onboard WS2812 on GP16 lights dim red immediately after its PIO initialization. It changes to dim green after storage, audio, and USB initialization have completed with no artificial delay. Both colors limit their active RGB channel to 4 of 255.

## Version

The firmware's version number is the `project()` version in [`Firmware/CMakeLists.txt`](../Firmware/CMakeLists.txt), such as `0.1.0`. Capabilities report it, and the app shows it as `FW`. A build from a working copy with uncommitted changes to tracked files reports it with `-dirty` appended. The UF2 metadata adds the commit, so `picotool info` shows `0.1.0 (<commit>)` and names the exact source. The reported text holds at most 16 characters, and a longer version fails the build.

Every change to the firmware raises the version number: the patch number for a fix, the minor number for a new capability, and the major number for a change that older apps cannot follow. [`Scripts/check-firmware-version.sh`](../Scripts/check-firmware-version.sh) is part of the complete gate. It fails when `Firmware` outside its tests, the shared C protocol and DSP sources, or the firmware section of `toolchain.json` differ from the merge base with `origin/main` while the version stays the same.

## TinyUSB port

The RP2 device port is the one in the pinned TinyUSB 0.21.0. Its `dcd_edpt_iso_activate` aborts a pending transfer before it reactivates an ISO endpoint, which keeps USB control responsive when audio restarts. The host fixture [`usb_iso_tests.c`](../Firmware/Tests/usb_iso_tests.c) compiles that port with TinyUSB's common RP2 source, and it fails when the abort is missing.

## USB interfaces

[`descriptors.c`](../Firmware/USB/descriptors.c) and [`tusb_config.h`](../Firmware/USB/tusb_config.h) define the following interfaces:

| Interface | Function |
| --- | --- |
| 0 | UAC2 control with a fixed 48 kHz clock and master mute/volume |
| 1 | Audio streaming, alternate 0 disabled, 1 PCM16, 2 packed PCM24 |
| 2 | Vendor-defined HID feature reports |
| 3 | SDK/picotool-compatible deferred BOOTSEL and flash reboot |

Both audio formats have two channels. The asynchronous OUT endpoint is `0x01`; feedback is `0x81`. The application supplies 16.16 feedback from its own audio ring. TinyUSB converts it to 10.14 for the three-byte full-speed endpoint through the patch described under [upstream notices](#upstream-notices). The intended qualification host is macOS, whose `usbaudiod` rejects every other feedback packet size with `device sent incorrect feedback packet size`.

Master volume uses signed 1/256 dB USB units with a one-dB advertised resolution. Bounds come from the canonical protocol's host-volume declarations. Host controls are separate from the profile's attenuation and mute. Volume preparation happens on the control core; a complete host-control value crosses to the audio owner through a bounded queue.

HID uses report ID 1 and usage page `0xff4e`, usage 1. The [wire codec](Protocol.md) owns the complete 256-byte report. The TinyUSB callbacks handle its 255 data bytes.

VID/PID `0xcafe/0x4014` are TinyUSB-style private development identifiers. They are not an allocated NeXTsound release identity. The configuration requests 500 mA bus power; this is not a measurement of board and amplifier consumption.

## Ownership and output

The control core owns TinyUSB, the device state machine, coefficient preparation, and the producer side of the 512-frame stereo ring. The audio core owns the renderer, DSP state, ring consumption, PIO, and DMA. Configuration and result queues carry copies rather than shared mutable DSP settings.

The [portable renderer](../Firmware/Core/render.c) primes to 192 frames, processes 48-frame blocks, applies host gain before the DSP, and gates the final output with a five-millisecond envelope. Its I2S words contain identical mono samples in both slots. Stream changes and underruns drain the envelope before clearing filter history and re-priming. Host mute does not change the stored profile settings.

[`Platform/i2s.c`](../Firmware/Platform/i2s.c) drives data on GP6 and side-set BCLK/LRCLK on GP14/GP15. Slots are 32 bits, MSB first. The generated [PIO program](../Firmware/Platform/i2s.pio) changes word clock one bit before the next slot's MSB. At the requested 150 MHz system clock, its exact fractional divider gives a nominal 48 kHz frame rate.

One DMA channel transfers explicitly bounded blocks from alternating buffers. There is no automatic chaining that could restart a channel at an advanced read pointer. The audio core prepares the next buffer while the current one transfers. Deadline misses and PIO TX stalls require hardware qualification.

A successful apply means the audio owner installed the complete prepared configuration for an upcoming block. Already queued audio is unchanged, and the DSP then crossfades its chains. Only acceptance advances the protocol generation. Persistence and verified-flash capabilities are enabled only after the [storage geometry and execution gates](Storage.md#geometry-and-execution-gates) pass. Two reserved sectors retain snapshots through a last-written commit page and complete readback. Persistence and reset pause the audio owner before flash or reboot operations; queued USB audio is discarded before a fresh stream epoch resumes.

Suspend drains to a silent block, stops DMA/PIO, drives the three audio pins low, and parks the audio core. Resume restarts from zero-filled output buffers and primes new input. The control core continues servicing USB. Total USB suspend current has not been qualified. Digital mute does not power down the amplifier.

## Telemetry

Runtime status reports digital input peak after host-volume processing and final output peak after transport gating. Underruns combine post-prime input starvation and detected PIO TX stalls. Overruns combine rejected/dropped input, DSP failures, and processing-deadline misses. These are 32-bit boot-session counters.

The read-only [diagnostic operation](Protocol.md#runtime-diagnostics-and-compatible-revisions) separates ring underruns, PIO stalls, rejected packets, DSP failures, and deadline misses. It also reports TinyUSB suspend/resume callback counts. The audio owner publishes source counters and aggregate status together. The USB owner adds its callback counts. Diagnostic reads do not change the active or saved profile.

`max_processing_us` measures the audio-owner control dequeue, configuration application, rendering, and telemetry publication. It excludes waiting for DMA and the output submission that follows. The nominal block deadline is 1000 microseconds. These fields become physical observations only after the image runs on the intended specimen.

## Verification boundary

```bash
bash Scripts/check.sh
```

The complete gate checks source formatting, formatting regression fixtures, SwiftLint, sanitized C suites, Swift tests, the Release package, and all three RP2350 targets. Firmware integration tests inspect the actual descriptor arrays, exercise the real USB callbacks against a platform fixture, drive the pinned TinyUSB audio class driver through its set-interface and feedback-completion paths to check the bytes that reach the feedback endpoint, and model the generated PIO instructions under the configured shift/autopull assumptions. They do not emulate the USB controller, DMA timing, pad signals, or amplifier.

Before installation, identify the intended specimen, establish physical flash geometry, preserve and verify its complete flash, and record restoration. A configured SDK flash size is not that measurement.

The [live diagnostic observations](Verification/Diagnostics-2026-10-18.json) identify clean firmware `e59f08cf` on serial `D4CDD489AFE28CC5`. Installation leaves both reserved sectors byte-identical. Original protocol-1.0 clients work alongside the new diagnostic client. Native PCM16/PCM24/PCM16 runs preserve digital profile mute and both default output UIDs. Ten malformed-request cases leave the snapshot and generation unchanged.

The live counters classify the single post-stop event as ring starvation. No sampled counter increment occurs during stable streaming. I2S stalls, DSP failures, and instrumented deadline misses stay zero. Immediate AudioUnit disposal does not remove the post-stop event, which remains visible in telemetry. During the maximum-filter PCM24 run, two saves produce 18 receive-side packet rejections. No DSP failure or deadline miss contributes to those aggregate overruns. The original canonical baseline is restored byte-identically and survives reboot as muted persisted generation 7 at -24 dB.

The instrumented high-water value for that boot session is 931 µs against the 1000 µs block deadline; it already exists before streaming. The next idle boot reports 933 µs. Neither value is a configuration-specific histogram or a universal unmuted timing guarantee. A targeted host suspend request returns success, but neither the port bit nor the firmware callback counters confirms a suspend/resume cycle. A separate idle-policy experiment opens only the unclaimed reset interface without capture or seize. It accepts a one-second idle timeout and acknowledges restoring the original timeout, but likewise produces no firmware suspend/resume notification. The cause remains open, and physical suspend/resume is not accepted.

Further exact-serial experiments close the helper's own device access before waiting, then additionally release and recreate its user client. Neither produces an observed suspended-port flag or firmware notification. Generation 7 remains muted and default output UIDs stay unchanged. The existing audio/HID owners and an additional device client attributed to ChatGPT remain untouched; their causal role is not established.

The host RP2 fixture also checks enabled suspend/resume interrupts, individual and jointly latched notification ordering, interrupt context, status-clear writes, and preservation of pending endpoint buffers. Independently removing either notification makes its negative control fail. These modeled interrupt cases do not qualify physical suspend/resume.

The [observations of October 24](Verification/Diagnostics-2026-10-24.json) installed clean firmware `953d75d4`, built against TinyUSB 0.21.0's own RP2 port, on the same specimen. Its name, saved snapshot and generation survive installation. Minor-0 capabilities omit the diagnostics flag, and minor-1 capabilities report it. Ten malformed requests leave the state unchanged. Muted PCM16, PCM24 with two saves, and PCM16 again change no counter during stable streaming. The saves reject 19 packets, and each stream end adds one ring underrun. A reboot restores the saved snapshot, and the previous unmuted snapshot is then restored byte-identically.

Every boot in that session exceeds the 1000 µs block deadline once before any stream, with two I2S stalls: 1183 µs with the unmuted profile and 1162 µs with its muted copy. The cause is open in [issue 167](https://github.com/phranck/NeXTsound/issues/167).

The [owner-metadata observations](Verification/Metadata-2026-10-24.json) installed firmware 0.2.0 over 0.1.0 on the same specimen. Its format-1 record loads with the same name, generation and snapshot. Metadata written in two parts reads back identically after a reboot, and clearing it again leaves the snapshot byte-identical to the state before the update.

Earlier datasets retain [storage/corruption recovery](Verification/Storage-2026-10-18.json), [format restart](Verification/AudioFormats-2026-10-18.json), [streaming storage](Verification/AudioStorageStress-2026-10-18.json), and the [unusable post-BOOTSEL SRAM counter method](Verification/RuntimeFollowup-2026-10-18.json). The SRAM zero words are not evidence of zero live counters.

Unmuted processing timing, runtime stack high-water use, I2S signals, wiring, and speaker safety remain unmeasured. Physical USB suspend and resume remain open in [issue 166](https://github.com/phranck/NeXTsound/issues/166).

## Upstream notices

The reset driver adapts Pico SDK 2.2.0's reset-interface driver and defers its action until audio quiescence. The descriptors adapt the [TinyUSB speaker example](https://github.com/hathach/tinyusb/tree/dae3f9a366bfcddbf9dcf1b48d7500286a849539/examples/device/uac2_speaker_fb). Its MIT notice, TinyUSB's MIT notice, and the Pico SDK BSD-3-Clause notice are retained in [`Firmware/ThirdParty`](../Firmware/ThirdParty). DSP provenance and its GPLv3 text are documented in [DSP.md](DSP.md).

`toolchain.json`'s `firmware.pico_sdk.tinyusb_commit` pins TinyUSB 0.21.0 directly from its own upstream repository rather than Pico SDK's bundled copy: every Pico SDK release through 2.3.1 still bundles the same TinyUSB commit from December 2024, which predates fixes relevant to this device's UAC2 + HID + vendor composite descriptor, including an RP2040 isochronous-endpoint-activation fix ([PR #2937](https://github.com/hathach/tinyusb/pull/2937)), an audio ISR-handling fix ([PR #3150](https://github.com/hathach/tinyusb/pull/3150)), and an RP2350-specific unaligned-memcpy hard fault fix in 0.21.0 itself. `Scripts/bootstrap-firmware.sh` fetches this commit directly from TinyUSB's own remote (which the Pico SDK submodule already points at) after the submodule checkout, rather than waiting for a Pico SDK release to carry it. TinyUSB 0.20.0 added USB Audio Class 1.0 support alongside the existing UAC2 implementation, renaming every UAC2-specific descriptor macro, enum, and struct with an explicit `20` suffix (for example `TUD_AUDIO_DESC_IAD` became `TUD_AUDIO20_DESC_IAD`); `Firmware/USB/descriptors.c`, `control.c`, and `nxs_usb.h` were updated to the renamed symbols. The `audio_control_request_t` convenience struct the original adapted example used to decode entity/channel/control-selector fields is no longer part of TinyUSB's core library (it only ever lived in example code, under a different, now-unused example); the callbacks decode `wIndex`/`wValue` directly with TinyUSB's own generic `TU_U16_HIGH`/`TU_U16_LOW` macros instead, matching the current upstream example's own pattern. The owner verified on hardware that the lockup from [issue 38](https://github.com/phranck/NeXTsound/issues/38) no longer occurs with this pin.

TinyUSB 0.21.0 no longer offers `CFG_TUD_AUDIO_ENABLE_FEEDBACK_FORMAT_CORRECTION` and formats the feedback endpoint by UAC version alone, so a full-speed UAC2 device would send 16.16 in four bytes on its three-byte endpoint, which the RP2350 driver splits into a three-byte and a one-byte packet and macOS rejects ([issue 43](https://github.com/phranck/NeXTsound/issues/43)). [`Firmware/ThirdParty/TinyUSB-0.21.0-feedback.patch`](../Firmware/ThirdParty/TinyUSB-0.21.0-feedback.patch) restores the 10.14 conversion behind that option.

TinyUSB 0.21.0 also sends a stream's first feedback packet before `tud_audio_set_itf_cb` runs, and closing a stream clears its feedback value to 0. A host that sizes its packets from that first value, such as [Circle](https://github.com/rsta2/circle) on the Raspberry Pi, then builds empty ones ([issue 61](https://github.com/phranck/NeXTsound/issues/61)). The same patch sends that packet after the callback, and the firmware sets the nominal 48 frames per millisecond in it until the ring level takes over.

`Scripts/bootstrap-firmware.sh` applies the patch after the checkout. Before moving the pin, and whenever the checkout holds an earlier version of the patch, it restores the files the patch touches. It refuses any other modification of the TinyUSB tree. The host test [`feedback_tests.c`](../Firmware/Tests/feedback_tests.c) is what catches a later TinyUSB bump that drops the patch.
