import AppKit
import Foundation
import NeXTsoundCore
import NeXTsoundWorkbench
import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
enum RenderWorkbench {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        if CommandLine.arguments[1] == "--document-type" {
            let metadata = [
                "identifier": ProfileFile.typeIdentifier,
                "file_extension": ProfileFile.fileExtension,
                "legacy_file_extension": ProfileFile.legacyFileExtension,
            ]
            let data = try JSONEncoder().encode(metadata)
            guard let json = String(bytes: data, encoding: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            print(json)
            return
        }
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.prohibited)
        try renderFrontPanel(connected: false, destination: destination)
        try renderFrontPanel(connected: true, destination: destination)
        try renderLibraryPanel(destination: destination)
        try renderAboutPanel(destination: destination)
    }
}

private extension RenderWorkbench {
    /// The scale both panels are rendered at.
    static let panelScale: CGFloat = 2

    static func renderFrontPanel(connected: Bool, destination: URL) throws {
        let profile = FactoryPreset.warm.makeProfile()
        let boards = connected ? BoardMonitor(discovery: PreviewBoardDiscovery()) : nil
        let model = try WorkbenchModel(library: ProfileLibrary(profiles: [profile], selectedID: profile.id), boards: boards)
        model.boards.start()
        // The preview board verifies through the main run loop, which a render that never runs it would never see.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        try renderPanel(
            FrontPanelView(model: model, driverLibrary: DriverLibraryModel()),
            stem: "front-panel" + (connected ? "-connected" : "") + "@2x",
            destination: destination
        )
    }

    /// Renders the Library panel with sample profiles, a speaker and a verified board.
    static func renderLibraryPanel(destination: URL) throws {
        let profiles = ["Soul Funk", "Flat", "Warm", "Speech", "Late Night", "Desk Monitor"].map { SoundProfile(name: $0) }
        let model = try WorkbenchModel(
            library: ProfileLibrary(profiles: profiles, selectedID: profiles[0].id),
            boards: BoardMonitor(discovery: PreviewBoardDiscovery())
        )
        model.boards.start()
        model.selectSpeaker(DriverRecord(name: "Dayton Audio CE41N-4"))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        try renderPanel(LibraryPanel(model: model, driverLibrary: DriverLibraryModel()), stem: "library-panel@2x", destination: destination)
    }

    /// Renders the About window with preview values, as the connected front panel renders a preview board. The icon
    /// is the installed app's, and the generic app icon where NeXTsound is not installed.
    static func renderAboutPanel(destination: URL) throws {
        let info = AboutInfo(version: "1.2.0", build: "34", copyright: "© 2026 LAYERED.work")
        let installedApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "work.layered.NeXTsound")
        let icon = installedApp.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .applicationBundle)
        try renderPanel(AboutPanel(info: info, icon: icon), stem: "about-panel@2x", destination: destination)
    }

    /// Renders a panel through SwiftUI's own renderer at scale 2, the scale its dots fall on whole device pixels at.
    /// The panels hold no AppKit view with an area, which only a window could draw.
    static func renderPanel(_ panel: some View, stem: String, destination: URL) throws {
        let renderer = ImageRenderer(content: panel)
        renderer.scale = panelScale
        guard let image = renderer.cgImage else {
            throw CocoaError(.fileWriteUnknown)
        }
        try writePNG(NSBitmapImageRep(cgImage: image), to: destination.appendingPathComponent(stem + ".png"))
        print("Rendered \(stem)")
    }

    static func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }
}

/// A fixed, instantly-verified board used only to render the connected UI state offscreen.
private struct PreviewBoardTransport: BoardTransport {
    func requestCapabilities() async throws -> DeviceCapabilities {
        var capabilities = DeviceCapabilities(serial: "D4CDD489AFE28CC5", firmwareVersion: "1.2.0")
        capabilities.deviceName = "Bedroom SoundBox"
        capabilities.flashSizeBytes = 4 * 1_048_576
        return capabilities
    }

    func setDeviceName(_: String) async throws {}

    func applyState(_: DeviceSnapshot) async throws {}

    func persistState() async throws {}

    /// Unsaved, so the connected render shows the storage state on the flash line, and streaming with sample values,
    /// so the status column shows live values.
    func requestStatus() async throws -> BoardStatusReading {
        var runtime = DeviceRuntimeStatus()
        runtime.isStreaming = true
        runtime.hostVolumeDb = -12
        runtime.maxProcessingUs = 410
        runtime.blockDeadlineUs = 1000
        runtime.storageIsAvailable = true
        return BoardStatusReading(runtime: runtime, storage: .unsaved)
    }

    func requestMetadata() async throws -> OwnerMetadata {
        OwnerMetadata()
    }

    func writeMetadata(_: OwnerMetadata) async throws {}
}

private final class PreviewBoardDiscovery: BoardDiscovery, @unchecked Sendable {
    func start(
        onConnect: @escaping @Sendable (BoardIdentitySnapshot, any BoardTransport) -> Void,
        onDisconnect _: @escaping @Sendable () -> Void
    ) {
        onConnect(BoardIdentitySnapshot(vendorID: 0x2E8A, productID: 0x000A, enumeratedSerial: "D4CDD489AFE28CC5"), PreviewBoardTransport())
    }

    func stop() {}
}
