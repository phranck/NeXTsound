import AppKit
import Foundation
import NeXTsoundCore
import NeXTsoundWorkbench
import SwiftUI

@main
@MainActor
enum RenderWorkbench {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        if CommandLine.arguments[1] == "--document-type" {
            let metadata = ["identifier": ProfileFile.typeIdentifier, "file_extension": ProfileFile.fileExtension]
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
        for scheme in [ColorScheme.light, .dark] {
            for size in [WorkbenchLayout.defaultSize, WorkbenchLayout.minimumSize] {
                try render(size: size, scheme: scheme, connected: false, destination: destination)
            }
        }
        try render(size: WorkbenchLayout.defaultSize, scheme: .light, connected: true, destination: destination)
    }
}

private extension RenderWorkbench {
    static func render(size: CGSize, scheme: ColorScheme, connected: Bool, destination: URL) throws {
        let appearance = scheme == .dark ? "dark" : "light"
        let nativeAppearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        NSApp.appearance = nativeAppearance
        let profile = FactoryPreset.warm.makeProfile()
        let boards = connected ? BoardMonitor(discovery: PreviewBoardDiscovery()) : nil
        let model = try WorkbenchModel(library: ProfileLibrary(profiles: [profile], selectedID: profile.id), boards: boards)
        model.boards.start()
        let content = WorkbenchView(model: model)
            .environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: content)
        host.appearance = nativeAppearance
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: -10000, width: size.width, height: size.height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderOut(nil)
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
        host.layoutSubtreeIfNeeded()
        guard
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        host.effectiveAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let stem = "workbench-\(Int(size.width))x\(Int(size.height))-\(appearance)" + (connected ? "-connected" : "")
        try data.write(to: destination.appendingPathComponent(stem + ".png"), options: .atomic)
        let report = RenderReport(
            width: size.width,
            height: size.height,
            appearance: appearance,
            source: "Offscreen rendering of the implemented SwiftUI view, not a running app screenshot.",
            windowVisible: window.isVisible,
            controls: controls(in: host, root: host)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: destination.appendingPathComponent(stem + ".json"), options: .atomic)
        print("Rendered \(stem)")
    }

    static func controls(in view: NSView, root: NSView) -> [ControlReport] {
        var result: [ControlReport] = []
        if let control = view as? NSControl {
            let frame = control.convert(control.bounds, to: root)
            result.append(ControlReport(
                type: String(describing: type(of: control)),
                frame: [frame.minX, frame.minY, frame.width, frame.height],
                fontPoints: control.font.map { Double($0.pointSize) },
                enabled: control.isEnabled
            ))
        }
        for child in view.subviews {
            result.append(contentsOf: controls(in: child, root: root))
        }
        return result
    }
}

private struct RenderReport: Codable {
    let width: Double
    let height: Double
    let appearance: String
    let source: String
    let windowVisible: Bool
    let controls: [ControlReport]
}

private struct ControlReport: Codable {
    let type: String
    let frame: [Double]
    let fontPoints: Double?
    let enabled: Bool
}

/// A fixed, instantly-verified board used only to render the connected UI state offscreen.
private struct PreviewBoardTransport: BoardTransport {
    func requestCapabilities() async throws -> DeviceCapabilities {
        var capabilities = DeviceCapabilities(serial: "D4CDD489AFE28CC5", firmwareVersion: "1.2.0")
        capabilities.deviceName = "Bedroom SoundBox"
        return capabilities
    }

    func setDeviceName(_: String) async throws {}

    func applyState(_: DeviceSnapshot) async throws {}

    func requestRuntimeStatus() async throws -> DeviceRuntimeStatus {
        DeviceRuntimeStatus()
    }
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
