# Development firmware

The RP2350 target integrates 48 kHz stereo UAC2 playback, vendor-defined HID control, and mono I2S output. Its entry point is [`Firmware/main.c`](../Firmware/main.c). This is a private bench build, not a hardware-qualified release.

## Build

```bash
bash Scripts/firmware.sh
```

The script bootstraps the pinned project-local tools, builds all three firmware targets, and inspects `nxs_firmware.uf2` as a file. It does not access a connected board or install firmware. Outputs are in `.build/firmware`. The separate `nxs_dsp_probe` target configures no USB or audio output. The SRAM-only `nxs_flash_probe` reads chip metadata over USB CDC; its ELF load ranges are checked during the build. See [flash identification and recovery](Backup.md).

`toolchain.json` supplies the board and dependency revisions. The program version identifies the Git revision and marks tracked working-tree changes. The audio firmware reserves 4 KiB stacks for both cores in the SDK's scratch banks. GCC emits `.su` frame reports beside its objects. These reports are not a measurement of interrupt-inclusive stack high-water use.

## USB interfaces

[`descriptors.c`](../Firmware/USB/descriptors.c) and [`tusb_config.h`](../Firmware/USB/tusb_config.h) define the following interfaces:

| Interface | Function |
| --- | --- |
| 0 | UAC2 control with a fixed 48 kHz clock and master mute/volume |
| 1 | Audio streaming, alternate 0 disabled, 1 PCM16, 2 packed PCM24 |
| 2 | Vendor-defined HID feature reports |

Both audio formats have two channels. The asynchronous OUT endpoint is `0x01`; feedback is `0x81`. The application supplies 16.16 feedback from its own audio ring. TinyUSB converts it to 10.14 for the three-byte full-speed endpoint. The intended qualification host is macOS.

Master volume uses signed 1/256 dB USB units with a one-dB advertised resolution. Bounds come from the canonical protocol's host-volume declarations. Host controls are separate from the profile's attenuation and mute. Volume preparation happens on the control core; a complete host-control value crosses to the audio owner through a bounded queue.

HID uses report ID 1 and usage page `0xff4e`, usage 1. The [wire codec](Protocol.md) owns the complete 256-byte report. The TinyUSB callbacks handle its 255 data bytes.

VID/PID `0xcafe/0x4014` are TinyUSB-style private development identifiers. They are not an allocated NeXTsound release identity. The configuration requests 500 mA bus power; this is not a measurement of board and amplifier consumption.

## Ownership and output

The control core owns TinyUSB, the device state machine, coefficient preparation, and the producer side of the 512-frame stereo ring. The audio core owns the renderer, DSP state, ring consumption, PIO, and DMA. Configuration and result queues carry copies rather than shared mutable DSP settings.

The [portable renderer](../Firmware/Core/render.c) primes to 192 frames, processes 48-frame blocks, applies host gain before the DSP, and gates the final output with a five-millisecond envelope. Its I2S words contain identical mono samples in both slots. Stream changes and underruns drain the envelope before clearing filter history and re-priming. Host mute does not change the stored profile settings.

[`Platform/i2s.c`](../Firmware/Platform/i2s.c) drives data on GP6 and side-set BCLK/LRCLK on GP14/GP15. Slots are 32 bits, MSB first. The generated [PIO program](../Firmware/Platform/i2s.pio) changes word clock one bit before the next slot's MSB. At the requested 150 MHz system clock, its exact fractional divider gives a nominal 48 kHz frame rate.

One DMA channel transfers explicitly bounded blocks from alternating buffers. There is no automatic chaining that could restart a channel at an advanced read pointer. The audio core prepares the next buffer while the current one transfers. Deadline misses and PIO TX stalls require hardware qualification.

A successful apply means the audio owner installed the complete prepared configuration for an upcoming block. Already queued audio is unchanged, and the DSP then crossfades its chains. Only acceptance advances the protocol generation. Persistence and verified-flash capabilities remain absent.

Suspend drains to a silent block, stops DMA/PIO, drives the three audio pins low, and parks the audio core. Resume restarts from zero-filled output buffers and primes new input. The control core continues servicing USB. Total USB suspend current has not been qualified. Digital mute does not power down the amplifier.

## Telemetry

Runtime status reports digital input peak after host-volume processing and final output peak after transport gating. Underruns combine post-prime input starvation and detected PIO TX stalls. Overruns combine rejected/dropped input, DSP failures, and processing-deadline misses. These are 32-bit boot-session counters.

`max_processing_us` measures the audio-owner control dequeue, configuration application, rendering, and telemetry publication. It excludes waiting for DMA and the output submission that follows. The nominal block deadline is 1000 microseconds. These fields become physical observations only after the image runs on the intended specimen.

## Verification boundary

```bash
bash Scripts/check.sh
```

The complete gate checks source formatting, formatting regression fixtures, SwiftLint, sanitized C suites, Swift tests, the Release package, and all three RP2350 targets. Firmware integration tests inspect the actual descriptor arrays, exercise the real USB callbacks against a platform fixture, and model the generated PIO instructions under the configured shift/autopull assumptions. They do not emulate the USB controller, DMA timing, pad signals, or amplifier.

Before installation, identify the intended specimen, establish physical flash geometry, preserve and verify its complete flash, and record restoration. A configured SDK flash size is not that measurement. USB enumeration, format/lifecycle behavior, runtime headroom, I2S signals, wiring, and speaker safety remain on-device acceptance work in [issue 3](https://github.com/phranck/NeXTsound/issues/3), following the storage/backup slice in [issue 9](https://github.com/phranck/NeXTsound/issues/9).

## Upstream notices

The descriptors adapt the SDK-pinned [TinyUSB speaker example](https://github.com/hathach/tinyusb/tree/86ad6e56c1700e85f1c5678607a762cfe3aa2f47/examples/device/uac2_speaker_fb). Its MIT notice, TinyUSB's MIT notice, and the Pico SDK BSD-3-Clause notice are retained in [`Firmware/ThirdParty`](../Firmware/ThirdParty). DSP provenance and its GPLv3 text are documented in [DSP.md](DSP.md).
