import AppKit
import Testing
@testable import NeXTsoundWorkbench

/// The windows stand far off every screen, so the tests never show one.
@MainActor
struct LibraryWindowAttachmentTests {
    /// An opening Library window stands the gap right of the front panel window with both tops in line, as its child
    /// window, which moves along when the front panel window moves, and it cannot be moved on its own.
    @Test func theLibraryWindowStaysBesideTheFrontPanelsRightEdge() {
        let windows = TestWindows()
        defer { windows.close() }
        let attachment = LibraryWindowAttachment()
        attachment.frontPanelWindowChanged(windows.frontPanel)
        attachment.libraryWindowChanged(windows.library)
        #expect(attachment.isLibraryOpen)
        #expect(windows.library.parent === windows.frontPanel)
        #expect(!windows.library.isMovable)
        expectBeside(windows)
        windows.frontPanel.setFrameOrigin(NSPoint(x: -19500, y: -19700))
        expectBeside(windows)
    }

    /// A Library window that opens before the front panel window is known, as a restored one can, attaches once the
    /// front panel window arrives.
    @Test func aLibraryWindowThatOpensFirstAttachesWhenTheFrontPanelArrives() {
        let windows = TestWindows()
        defer { windows.close() }
        let attachment = LibraryWindowAttachment()
        attachment.libraryWindowChanged(windows.library)
        #expect(windows.library.parent == nil)
        attachment.frontPanelWindowChanged(windows.frontPanel)
        #expect(windows.library.parent === windows.frontPanel)
        expectBeside(windows)
    }

    /// Closing the Library window releases the key and detaches the window.
    @Test func closingTheLibraryWindowReleasesTheKey() {
        let windows = TestWindows()
        defer { windows.close() }
        let attachment = LibraryWindowAttachment()
        attachment.frontPanelWindowChanged(windows.frontPanel)
        attachment.libraryWindowChanged(windows.library)
        windows.library.close()
        #expect(!attachment.isLibraryOpen)
        #expect(windows.library.parent == nil)
    }

    /// A drag on the Library panel moves the front panel window by the pointer's way on the screen, counted from
    /// where the pointer went down, and the Library window moves along.
    @Test func aDragOnTheLibraryMovesTheFrontPanelWindow() {
        let windows = TestWindows()
        defer { windows.close() }
        let attachment = LibraryWindowAttachment()
        attachment.frontPanelWindowChanged(windows.frontPanel)
        attachment.libraryWindowChanged(windows.library)
        let origin = windows.frontPanel.frame.origin
        // The drag starts 10 points right of and 4 points below where the pointer went down, at screen point (100, 50).
        attachment.dragFrontPanel(translation: CGSize(width: 10, height: 4), pointer: NSPoint(x: 110, y: 46))
        #expect(windows.frontPanel.frame.origin == NSPoint(x: origin.x + 10, y: origin.y - 4))
        attachment.dragFrontPanel(translation: CGSize(width: 30, height: -20), pointer: NSPoint(x: 130, y: 70))
        #expect(windows.frontPanel.frame.origin == NSPoint(x: origin.x + 30, y: origin.y + 20))
        expectBeside(windows)
    }

    /// AppKit pulls a titled window back onto the screen when it orders the window front, which put the Library window
    /// over the front panel window once the front panel window stood at the screen's right edge. The front panel window
    /// moves left instead, until the Library window fits beside it on the screen. The windows stand on the main screen
    /// for that, fully transparent.
    @Test func theScreensEdgeNeverPushesTheLibraryWindowOverTheFrontPanel() throws {
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        let frontPanel = transparentTitledWindow(NSRect(x: visible.midX - 300, y: visible.midY - 200, width: 600, height: 400))
        let library = transparentTitledWindow(NSRect(x: visible.midX, y: visible.midY, width: 218, height: 300))
        defer {
            library.close()
            frontPanel.close()
        }
        frontPanel.orderFront(nil)
        let attachment = LibraryWindowAttachment()
        attachment.frontPanelWindowChanged(frontPanel)
        attachment.libraryWindowChanged(library)
        frontPanel.setFrameOrigin(NSPoint(x: visible.maxX - frontPanel.frame.width, y: frontPanel.frame.minY))
        library.orderFront(nil)
        #expect(
            library.frame.minX == frontPanel.frame.maxX + LibraryWindowAttachment.gap,
            "Library \(library.frame), front panel \(frontPanel.frame)"
        )
        #expect(library.frame.maxX <= visible.maxX, "Library \(library.frame), screen \(visible)")
    }

    /// The Library window following its moving front panel window off the screen is no reason to move the front panel
    /// window back, so a drag toward the screen's edge goes where the pointer takes it.
    @Test func followingTheFrontPanelOffTheScreenLeavesTheFrontPanelWhereItWasMoved() throws {
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        let frontPanel = transparentTitledWindow(NSRect(x: visible.midX - 300, y: visible.midY - 200, width: 600, height: 400))
        let library = transparentTitledWindow(NSRect(x: visible.midX, y: visible.midY, width: 218, height: 300))
        defer {
            library.close()
            frontPanel.close()
        }
        frontPanel.orderFront(nil)
        let attachment = LibraryWindowAttachment()
        attachment.frontPanelWindowChanged(frontPanel)
        attachment.libraryWindowChanged(library)
        let rightEdge = NSPoint(x: visible.maxX - frontPanel.frame.width, y: frontPanel.frame.minY)
        frontPanel.setFrameOrigin(rightEdge)
        #expect(frontPanel.frame.origin == rightEdge)
        #expect(library.frame.minX == frontPanel.frame.maxX + LibraryWindowAttachment.gap)
    }
}

/// A front panel window and a Library window of the panels' sizes, far off every screen.
@MainActor
private struct TestWindows {
    let frontPanel = testWindow(NSRect(x: -20000, y: -20000, width: 1189, height: 704))
    let library = testWindow(NSRect(x: -22000, y: -22000, width: 218, height: 635))

    func close() {
        library.close()
        frontPanel.close()
    }
}

@MainActor
private func testWindow(_ frame: NSRect) -> NSWindow {
    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
}

/// A window with a hidden, full-size title bar like the panels' windows, which shows nothing because it is fully
/// transparent.
@MainActor
private func transparentTitledWindow(_ frame: NSRect) -> NSWindow {
    let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.alphaValue = 0
    window.isReleasedWhenClosed = false
    return window
}

/// Expects the Library window's left edge the gap right of the front panel window's right edge and both tops in line.
@MainActor
private func expectBeside(_ windows: TestWindows, sourceLocation: SourceLocation = #_sourceLocation) {
    let frontPanel = windows.frontPanel.frame
    let library = windows.library.frame
    #expect(
        library.minX == frontPanel.maxX + LibraryWindowAttachment.gap,
        "Library \(library), front panel \(frontPanel)",
        sourceLocation: sourceLocation
    )
    #expect(library.maxY == frontPanel.maxY, "Library \(library), front panel \(frontPanel)", sourceLocation: sourceLocation)
}
