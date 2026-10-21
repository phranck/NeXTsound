# Portable mono DSP

`Shared/Sources/NeXTsoundDSP` is the C processing engine shared by the firmware build and the Swift EQ preview. Its declarations are in [`nxs_dsp.h`](../Shared/Sources/NeXTsoundDSP/include/nxs_dsp.h).

## Signal path

The engine accepts normalized interleaved stereo and produces mono. Each input channel is bounded to full scale; nonfinite input samples become zero. The signal path is stereo averaging, a second-order Butterworth high-pass, five peaking filters, attenuation, peak limiting, and mute. Filter and parameter limits come from the protocol target.

The limiter has instantaneous attack and a configurable exponential gain release. Its output is bounded by the configured digital peak ceiling. This is not a thermal or excursion protection model for a loudspeaker.

Mute suppresses output while the filters continue processing. Initialization uses the canonical muted default settings.

## Closed-box alignment

The engine's high-pass is a fixed-Q (1/√2, Butterworth) electronic filter: only its corner frequency (`highPassHz`) is ever configurable, never its Q. That electronic filter is separate from the driver-in-box acoustic response the sealed enclosure itself produces, which has its own second-order corner frequency (Fc) and total Q (Qtc), set entirely by the driver's free-air parameters (Fs, Qts, Vas) and the enclosure's net internal air volume (Vb):

```
alpha = Vas / Vb
Fc = Fs * sqrt(1 + alpha)
Qtc = Qts * sqrt(1 + alpha)
```

`NeXTsoundCore.ClosedBoxAlignment` computes this deterministically from a `DriverRecord` and a Vb in liters, and classifies the result against the commonly published alignment chart (Bessel, Butterworth, Chebyshev, and over-/underdamped). A missing Fs, Qts, or Vas throws a specific, named error rather than silently falling back to a default; it is a predicted acoustic response, not a measurement, and is kept distinct from the electronic high-pass and EQ preview below. `ClosedBoxAlignment.init(driver:enclosure:)` reads Vb from an `EnclosureRecord`'s own `volume.netLiters` rather than a second, hand-copied figure.

Selecting a speaker in the workbench sidebar (`WorkbenchModel.selectSpeaker`) uses this: when the chosen driver's Fs, Qts, and Vas are all known, the electronic high-pass is enabled and set to the alignment's corner frequency against the one fixed enclosure (`EnclosureRecord.nextSoundBoxMini()`). A driver missing any of the three leaves the high-pass exactly as it was. This is deliberately the only DSP setting speaker selection computes: the EQ bands, attenuation, and limiter each need the amplifier/supply voltage transfer between a digital level and the speaker terminals to set to a physically meaningful value, and this project does not have that calibration yet ([issue 19](https://github.com/phranck/NeXTsound/issues/19)).

Vb for the one fixed enclosure comes from [`Documentation/Verification/Enclosure-2026-10-21.json`](Verification/Enclosure-2026-10-21.json): the owner's own CAD modeled the interior air cavity as its own solid, exported separately from the driver and the RP2350 board, with each part's volume computed via the divergence theorem over its mesh.

## Audio ownership

Call `nxs_dsp_prepare` outside the audio thread to compute a complete configuration. Invalid snapshots leave the destination unchanged. The audio thread owns its `nxs_dsp_t` and calls `nxs_dsp_apply` at a block boundary. A second apply is refused while a transition is active.

The engine crossfades two complete processing chains over `NXS_DSP_TRANSITION_FRAMES`. During a transition, the output also obeys the incoming configuration's limiter ceiling. Old and new chains have independent delay and limiter state. The extra work of a transition belongs in the eventual on-device runtime budget.

`nxs_dsp_process` accepts no more than `NXS_DSP_BLOCK_FRAMES` per call. Rejection leaves the engine unchanged. It allocates no memory and calls no USB or flash API. The caller provides input/output buffers and handles device synchronization. `nxs_dsp_reset_history` clears both chains' signal history and meters without changing their prepared settings or transition progress. The renderer uses it only after its output envelope has reached silence.

## EQ preview

`nxs_dsp_eq_magnitude` evaluates the same coefficients used by the processing engine. Swift's `EQResponse` prepares those coefficients once and exposes the result in decibels. The preview includes the linear high-pass and EQ stages only. It excludes attenuation, mute, and nonlinear limiting and does not describe the speaker's acoustic response.

## Build and test

Run all shared tests, formatting/lint checks, the Release package build, and the RP2350 cross-build:

```bash
bash Scripts/check.sh
```

Build the firmware targets:

```bash
bash Scripts/firmware.sh
```

The firmware bootstrap currently supports an Apple Silicon macOS build host. `toolchain.json` pins the compiler archive/checksum, SDK commit, TinyUSB commit, and build-time picotool commit. Tools and dependencies are installed under ignored `.tools`. The first run downloads them. The local and CI gates use the same manifest.

`Firmware/probe.c` requests the canonical 150 MHz clock and exercises the muted engine without configuring USB, UART output, or I²S. Outputs are under `.build/firmware`, including `nxs_dsp_probe.elf` and `nxs_dsp_probe.uf2`. The same build also produces the [USB audio/HID firmware](Firmware.md) as `nxs_firmware.elf` and `nxs_firmware.uf2`. The probe remains a separate no-I/O target. The build script inspects the firmware file but never installs it or accesses a device. The SDK's configured flash size is not a physical flash measurement.

Host tests cover stereo normalization, analytic and processed filter response, DC rejection with a Float32 tolerance, limiting/release, transitions, malformed settings/samples, configuration aliasing, and parameter corners. The cross-build establishes that the RP2350 target compiles and links. Runtime timing, I²S signals, USB behavior, and speaker safety require separate hardware verification.

## Upstream material

The transposed direct-form biquad step is adapted from [DSPi v1.1.5](https://github.com/WeebLabs/DSPi/blob/5d4dd00f82637fdf8d275f80aeaff0fd7b62719a/firmware/DSPi/dsp_biquad.h). The source identifies the upstream revision and the NeXTsound adaptation date. The unchanged [GPLv3 text](../Shared/Sources/NeXTsoundDSP/LICENSE) accompanies this target.

[Pico SDK 2.2.0](https://github.com/raspberrypi/pico-sdk/tree/a1438dff1d38bd9c65dbd693f0e5db4b9ae91779) retains its [BSD-3-Clause notice](https://github.com/raspberrypi/pico-sdk/blob/a1438dff1d38bd9c65dbd693f0e5db4b9ae91779/LICENSE.TXT) in the fetched checkout. The firmware build uses the SDK rather than copying board-support sources into this repository.
