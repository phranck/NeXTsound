# Native workbench

NeXTsound is a SwiftUI app with one ordinary main window targeting macOS 15 and later, managing a local profile library. It discovers compatible SoundBoxes and shows their connection status, custom name, and firmware version through a read-only capabilities query, can write a new persisted name to the board, and can apply the current profile's DSP settings to the board for live listening. Neither write persists DSP state to board flash, resets the board, nor changes the system audio output; a reconnect or power cycle reverts to the board's last persisted DSP state. Generation-aware negotiation, retries, volatile A/B, and an explicit device-save workflow remain tracked in [issue 16](https://github.com/phranck/NeXTsound/issues/16).

## Build

From the repository root:

```bash
bash Scripts/app.sh
```

The command selects the Xcode version from `toolchain.json`, bootstraps the checksum-pinned XcodeGen, generates `App/NeXTsound.xcodeproj`, and builds Debug and Release without signing. It does not launch or install the app.

Build products:

- `.build/macOS/Build/Products/Debug/NeXTsound.app`
- `.build/macOS/Build/Products/Release/NeXTsound.app`

The complete repository gate is `bash Scripts/check.sh`. It includes shared and app package tests, formatting/lint, Release packages, all RP2350 targets and guards, and both native app configurations.

## Profile library

`ProfileLibrary` is the internally managed collection of profiles; `ProfileLibraryStore` persists it as validated atomic local JSON under Application Support, independent of any file the user opens or saves. `ProfileFile` wraps the existing `SoundProfile` for exactly one purpose: it is the `FileDocument` adapter behind SwiftUI's `fileImporter`/`fileExporter`, so a profile's canonical validated JSON can be imported or exported explicitly. The native file extension is `.nxsprofile`; JSON profiles can also be imported. The app owns the exported `.nxsprofile` UTI but is not registered as a document editor for it or for generic JSON, since neither drives the app's lifecycle.

`WorkbenchModel` is the single `@Observable` source of truth: it owns the library, mediates every mutation through validation, registers native undo via the window's `UndoManager`, and debounces persistence. A failed load never blocks editing or quitting; it surfaces through the storage status line while edits continue in memory until storage recovers.

## Driver library

`DriverRecord` is a driver model entry the owner maintains by hand: Thiele/Small, electrical, mechanical, thermal, and dimensional parameters, a name/manufacturer, and an optional source. Missing parameters stay `nil` rather than defaulted. `DriverLibrary` is the validated collection, seeded by default with the one driver currently in use, Tectonic Elements TEBM28C10-4; `DriverLibraryStore` persists it as atomic local JSON under Application Support, the same pattern `ProfileLibraryStore` uses (both now share the bounded atomic read/write in `AtomicJSONFile`). `DriverLibraryModel` is the `@Observable` CRUD state behind the "Driver models" toolbar sheet; it holds no reference to `BoardMonitor` or any board transport, so adding, editing, or removing a driver model never writes to a connected board. A selected entry's parameters are copied into a profile's `SpeakerRecord` snapshot rather than referenced live, matching the existing catalog/snapshot separation; the DSP calculation that reads a selected entry is [issue 19](https://github.com/phranck/NeXTsound/issues/19)'s own work.

An accepted edit advances the profile revision atomically. Failed edits and exhausted revisions leave the library unchanged. An incomplete name can remain in the editor but fails validation on export. A preset replaces DSP settings and preset origin without discarding a profile's identity, name, speaker, or enclosure snapshots. Starting presets remain digitally muted.

The analytical preview uses the shared DSP coefficients. It excludes attenuation, mute, and nonlinear limiting and is not an acoustic measurement. The display clips graph coordinates at its labeled vertical range without altering the underlying settings.

## Localization

The app is localized into English (development language) and German. Three String Catalogs carry the translations: `App/Application/InfoPlist.xcstrings` for the bundle name and the exported document type's description, `NeXTsoundWorkbench`'s own `Resources/Localizable.xcstrings` for every UI string in the workbench, and `NeXTsoundCore`'s own `Resources/Localizable.xcstrings` for the shared model's validation and factory-preset strings. Each Swift package declares `defaultLocalization: "en"` and ships its catalog as a processed resource, so `Text`/`Button`/`.help(...)` literals resolve through the package's own resource bundle rather than the app's.

A `LocalizedError.errorDescription` or any other computed `String` built from a literal is not picked up by Xcode's source scanner on its own; each one is wrapped in `String(localized:)` so it participates in the catalog. `WireError`'s message is the one deliberate exception: it comes from the shared C protocol library's `nxs_result_description`, a wire-protocol debug string compiled into firmware and host alike, and stays English-only rather than duplicating a translation table across the Swift/C boundary.

Every toolbar action control has a `.help(...)` tooltip, translated alongside its label.

## Board discovery

`BoardMonitor` tracks one `BoardConnectionState`: disconnected, detected (matched by USB identity, not yet verified), verified (with the firmware's reported `DeviceCapabilities`), or mismatched (an invalid reply or a reported serial that disagrees with the enumerated device). `IOHIDBoardDiscovery` finds compatible boards through `IOHIDManager`, matching the canonical vendor/product ID and HID usage from `BoardIdentity`, without seizing the device. `USBHostBoardTransport` sends exactly one non-mutating capabilities request as a raw USB class control transfer and validates its reply's identity, operation, and size before decoding it; it never sends an apply, persist, or reset request. The transfer goes through the `NXSUSBHostShim` C target's libusb call rather than `IOHIDDeviceSetReport`/`GetReport` or Apple's IOUSBHost framework: on this composite descriptor (Audio + HID + vendor reset), the HID report path truncates the reply, and IOUSBHost's `IOUSBHostInterface`/`IOUSBHostDevice` both require exclusive access that collides with the system's own HID and Audio drivers already attached to the device's other interfaces, while libusb's control-transfer path claims nothing. Report exchange runs off the main thread; reconnecting after a disconnect never resends a stale reply.

Both discovery and transport are protocols so tests inject fakes for disconnect/reconnect, stale or malformed replies, and identity mismatches without a physical board.

The header badge's pencil button opens a rename form that writes a new name to the board via the `SET_NAME` wire operation; the firmware stores it in a fixed 32-byte flash field alongside the DSP snapshot (`Firmware/Core/storage.c`). `BoardMonitor.setDeviceName(_:)` re-queries capabilities after a successful write so the badge reflects the new name immediately, but the name is read by macOS only at USB enumeration, so the renamed board keeps its old name until it resets or is replugged.

`Firmware/USB/descriptors.c`'s `tud_descriptor_string_cb` serves the name under two separate USB string indices, both falling back to their own fixed literal when unset: index 2 is the device's `iProduct` string, read by `system_profiler SPUSBDataType` and `ioreg`'s `kUSBProductString`, and index 4 is the Audio Control interface's own `iInterface` string (set via `TUD_AUDIO_DESC_STD_AC`'s third argument in the configuration descriptor), which is what macOS Sound settings, Audio MIDI Setup, and `system_profiler SPAudioDataType` actually name the device from. Updating only index 2 left Sound settings showing the fixed literal after a rename (issue 27); both indices must track `product_name` together.

Unlike the capabilities request, `SET_NAME` replies only after its flash write completes, which outlasts its own USB transaction; a one-shot transfer observed against the bench specimen returned whatever reply the device had buffered from the previous exchange and failed to validate. `USBHostBoardTransport.exchangeUntilComplete` resends the identical request and polls its reply up to an overall ten-second budget instead, which the device accepts as the same request already in flight rather than a new one.

A "Send to SoundBox" toolbar action, enabled only once the board is `.verified`, sends the current profile's DSP settings via the `APPLY_STATE` wire operation (`BoardMonitor.apply(_:)`, `WorkbenchModel.applyToBoard()`), exactly as edited. It never writes to flash, so a reconnect or power cycle reverts to the board's last persisted generation. On-device verification on 2026-10-20 confirmed the full path: an applied snapshot reads back from `READ_STATE` with the exact edited values, and the specimen was audible. The specimen's speaker safety margins (excursion, thermal) are still not established (see [issue 3](https://github.com/phranck/NeXTsound/issues/3)); the owner accepted that risk explicitly for this verification after confirming the path worked, rather than the app clamping it.

## Fixed enclosure data

The [scalar enclosure record](Verification/Enclosure-2026-10-18.json) supplies geometric references for the planned driver workflow. It records the mounting interface, source digest, coordinate system, named air region, method, and remaining uncertainties. The source CAD and working geometry stay private outside Git.

Its air region uses an explicit virtual front closure. It is not a qualified sealed acoustic volume. The remaining component displacement and leakage are unknown. Catalog eligibility must check the entire mounting/clearance envelope, and the calculation must retain these model conditions. The current offline editor does not yet consume this record.

## Reproducible configuration

- `toolchain.json` owns the Xcode and generator pins.
- `App/Workbench/Package.swift` owns the native deployment minimum.
- `ProfileFile` owns the exported profile's type identifier and file extension.
- `WorkbenchLayout` owns default/minimum view sizes.
- `ResponsePlotGeometry` owns the plotted gain limit.

`Scripts/app.sh` derives generator environment values from these sources. `NeXTsoundWorkbenchRender --document-type` emits the exported profile's type JSON without creating a window or initializing the rendering application. The generated Xcode project and property lists stay ignored. The generator runs from its packaged executable so its bundled setting presets remain available.

The `NXSUSBHostShim` target links Homebrew's `libusb` (`brew install libusb`) from `/opt/homebrew`, unlike the checksum-pinned tools above; it is not version-pinned. Homebrew on Apple Silicon only ships an arm64 build, so the app targets `ARCHS: arm64` in `App/project.yml` rather than the default universal set.

## Tests and rendering

```bash
xcrun swift test --package-path App/Workbench
xcrun swift run --package-path App/Workbench NeXTsoundWorkbenchRender "$PWD/.build/app-render"
```

The renderer creates its own hidden offscreen window with activation prohibited. It writes light/dark images at the default and minimum sizes, plus native control bounds and font measurements. These images show the implemented SwiftUI content, not screenshots of a running NeXTsound application. At minimum height, the editor supports vertical scrolling.

Tests cover canonical round trips, malformed input, directory rejection, revision/identity failures, atomic edits, metadata preservation, analytical response, display geometry, library validation/limits, store load/save/corruption recovery, board disconnect/reconnect, stale and malformed replies, identity mismatch, device name round trips (including the shared space-permitting validation and the firmware's fixed-length flash storage), a broken store never blocking the model from becoming ready, the driver library's validation, persistence round trips, and its independence from any connected board, and the live-apply action sending the edited profile's settings unchanged, with error surfacing on failure and without a connection. The directory case was observed crashing before checking `isRegularFile` ahead of `regularFileContents`.

Localization has no dedicated test suite; it is verified by the build producing a `de.lproj` bundle for the app target and for each Swift package's resource bundle, and by every string catalog key holding a German translation.

[Verification evidence](Verification/Workbench-2026-10-19.json) separates builds, model/library/store/board tests, and offscreen rendering. [A follow-up record](Verification/Workbench-2026-10-19-capabilities-fix.json) covers the first successful live capabilities round trip through the actual shipped app, launched visibly against the bench specimen. Interactive native menu/dialog workflows and runtime behavior on macOS 15 have still not been exercised by these checks. The owner maintains the driver model catalog by hand in [issue 15](https://github.com/phranck/NeXTsound/issues/15); the fixed enclosure geometry is [issue 17](https://github.com/phranck/NeXTsound/issues/17). [Issue 19](https://github.com/phranck/NeXTsound/issues/19) calculates and optimizes the profile from a selected driver's available usable parameters, while [issue 20](https://github.com/phranck/NeXTsound/issues/20) adds volatile A/B. These are planned features, not capabilities of the current workbench.
