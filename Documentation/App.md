# Native offline workbench

NeXTsound includes a SwiftUI document-based app targeting macOS 15 and later. The current slice edits local profiles only. It does not discover USB devices, apply settings to a board, play audio, or change the system audio output. Live device integration is tracked in [issue 16](https://github.com/phranck/NeXTsound/issues/16).

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

## Profile documents

`ProfileDocument` wraps the existing `SoundProfile`. Its file contents are the canonical validated JSON, not a separate app schema. The native file extension is `.nxsprofile`; JSON profiles can also be opened. The app registers as the owner of its own format and as an alternate handler for generic JSON.

Apple's [FileDocument](https://developer.apple.com/documentation/swiftui/filedocument) and [DocumentGroup](https://developer.apple.com/documentation/swiftui/documentgroup) supply document open/save, multiple documents, change tracking, and undo for document-value changes. Serialization is not main-actor isolated. The toolbar delegates open/save to the native document responder chain.

An accepted edit advances the profile revision atomically. Failed edits and exhausted revisions leave the document unchanged. An incomplete name can remain in the editor but fails validation when saved. A preset replaces DSP settings and preset origin without discarding document identity, name, speaker, or enclosure snapshots. Starting presets remain digitally muted.

The analytical preview uses the shared DSP coefficients. It excludes attenuation, mute, and nonlinear limiting and is not an acoustic measurement. The display clips graph coordinates at its labeled vertical range without altering the underlying settings.

## Reproducible configuration

- `toolchain.json` owns the Xcode and generator pins.
- `App/Workbench/Package.swift` owns the native deployment minimum.
- `ProfileDocument` owns the document type identifier and file extension.
- `WorkbenchLayout` owns default/minimum view sizes.
- `ResponsePlotGeometry` owns the plotted gain limit.

`Scripts/app.sh` derives generator environment values from these sources. `NeXTsoundWorkbenchRender --document-type` emits document-type JSON without creating a window or initializing the rendering application. The generated Xcode project and property lists stay ignored. The generator runs from its packaged executable so its bundled setting presets remain available.

## Tests and rendering

```bash
xcrun swift test --package-path App/Workbench
xcrun swift run --package-path App/Workbench NeXTsoundWorkbenchRender "$PWD/.build/app-render"
```

The renderer creates its own hidden offscreen window with activation prohibited. It writes light/dark images at the default and minimum sizes, plus native control bounds and font measurements. These images show the implemented SwiftUI content, not screenshots of a running NeXTsound application. At minimum height, the editor supports vertical scrolling.

Document/model tests cover canonical round trips, malformed input, directory rejection, revision/identity failures, atomic edits, metadata preservation, analytical response, and display geometry. The directory case was observed crashing before checking `isRegularFile` ahead of `regularFileContents`.

[Verification evidence](Verification/Workbench-2026-10-18.json) separates builds, model tests, and offscreen rendering. Native menu/dialog interaction, a visible GUI session, and runtime behavior on macOS 15 have not been exercised by these checks. Speaker/enclosure editing and volatile A/B are tracked in [issue 15](https://github.com/phranck/NeXTsound/issues/15).
