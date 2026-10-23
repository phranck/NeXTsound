import AppKit
import Testing
@testable import NeXTsoundWorkbench

/// The windows stand far off every screen, so the tests never show one.
@MainActor
struct LibraryWindowAttachmentTests {
    /// An opening Library window sits at the front panel window's right edge with both tops in line, as its child
    /// window, which moves along when the front panel window moves, and it cannot be moved on its own.
    @Test func theLibraryWindowStaysGluedToTheFrontPanelsRightEdge() {
        let windows = TestWindows()
        defer { windows.close() }
        let attachment = LibraryWindowAttachment()
        attachment.frontPanelWindowChanged(windows.frontPanel)
        attachment.libraryWindowChanged(windows.library)
        #expect(attachment.isLibraryOpen)
        #expect(windows.library.parent === windows.frontPanel)
        #expect(!windows.library.isMovable)
        expectGlued(windows)
        windows.frontPanel.setFrameOrigin(NSPoint(x: -19500, y: -19700))
        expectGlued(windows)
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
        expectGlued(windows)
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
        expectGlued(windows)
    }
}

/// A front panel window and a Library window of the panels' sizes, far off every screen.
@MainActor
private struct TestWindows {
    let frontPanel = testWindow(NSRect(x: -20000, y: -20000, width: 1189, height: 704))
    let library = testWindow(NSRect(x: -22000, y: -22000, width: 206, height: 635))

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

/// Expects the Library window's left edge on the front panel window's right edge and both tops in line.
@MainActor
private func expectGlued(_ windows: TestWindows, sourceLocation: SourceLocation = #_sourceLocation) {
    let frontPanel = windows.frontPanel.frame
    let library = windows.library.frame
    #expect(library.minX == frontPanel.maxX, "Library \(library), front panel \(frontPanel)", sourceLocation: sourceLocation)
    #expect(library.maxY == frontPanel.maxY, "Library \(library), front panel \(frontPanel)", sourceLocation: sourceLocation)
}
