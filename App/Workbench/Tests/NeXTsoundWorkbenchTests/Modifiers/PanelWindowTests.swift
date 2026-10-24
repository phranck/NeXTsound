import AppKit
import NeXTsoundCore
import SwiftUI
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct PanelWindowTests {
    /// The front panel reaches under its window's hidden title bar, and the window still takes the panel's own size,
    /// so the metal reaches from the window's top edge to its bottom edge.
    @Test func theWindowIsAsTallAsTheFrontPanel() async throws {
        let profile = FactoryPreset.warm.makeProfile()
        let model = try WorkbenchModel(library: ProfileLibrary(profiles: [profile], selectedID: profile.id))
        try await expectWindowFits(FrontPanelView(model: model, driverLibrary: DriverLibraryModel()))
    }

    /// The About window shows nothing of its title bar, so its close, minimize and zoom buttons are hidden once the
    /// panel stands in it.
    @Test func theAboutWindowHidesItsButtons() async throws {
        let info = AboutInfo(version: "1.2.0", build: "34", copyright: nil)
        let about = hostingWindow(
            for: AboutPanel(info: info, icon: NSImage()),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView]
        )
        defer {
            about.window.close()
        }
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = kinds.compactMap { about.window.standardWindowButton($0) }
        try #require(buttons.count == kinds.count, "The window has \(buttons.count) of its \(kinds.count) buttons.")
        let hidden = await waitUntil { buttons.allSatisfy(\.isHidden) }
        #expect(hidden, "Visible buttons: \(buttons.filter { !$0.isHidden }.count)")
    }
}

/// Hosts a panel the way a scene with a hidden title bar and content-sized resizability does, and expects the window
/// to take the size that a window without a title bar takes for the same panel, with the metal in every pixel of the
/// window's first and last rows.
///
/// The panel's size comes from a window on the same screen, because the dot grids snap to its pixels, so the panel
/// is a different number of points tall at another display scale.
@MainActor
private func expectWindowFits(_ panel: some View, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    let untitled = hostingWindow(for: panel, styleMask: [.borderless])
    let titled = hostingWindow(for: panel, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView])
    defer {
        untitled.window.close()
        titled.window.close()
    }
    let view = titled.controller.view
    let hasTitleBar = await waitUntil { view.safeAreaInsets.top > 0 }
    try #require(hasTitleBar, "The window has no title bar to reach under.", sourceLocation: sourceLocation)
    let panelSize = untitled.controller.preferredContentSize
    let fits = await waitUntil { titled.controller.preferredContentSize == panelSize }
    #expect(
        fits,
        "The window asks for \(titled.controller.preferredContentSize), the panel is \(panelSize).",
        sourceLocation: sourceLocation
    )
    titled.window.setContentSize(titled.controller.preferredContentSize)
    view.layoutSubtreeIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    for row in [0, bitmap.pixelsHigh - 1] {
        let uncovered = (0 ..< bitmap.pixelsWide).first { column in
            (bitmap.colorAt(x: column, y: row)?.alphaComponent ?? 0) < 1
        }
        #expect(
            uncovered == nil,
            "Pixel row \(row) of \(bitmap.pixelsHigh) shows no metal at column \(uncovered ?? -1).",
            sourceLocation: sourceLocation
        )
    }
}

/// A window whose content is `panel` and whose size follows the size the panel asks for.
@MainActor
private func hostingWindow<Panel: View>(
    for panel: Panel,
    styleMask: NSWindow.StyleMask
) -> (window: NSWindow, controller: NSHostingController<Panel>) {
    let controller = NSHostingController(rootView: panel)
    controller.sizingOptions = [.preferredContentSize]
    let window = NSWindow(contentViewController: controller)
    window.styleMask = styleMask
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    return (window, controller)
}
