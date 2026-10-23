import AppKit
import Observation
import SwiftUI

/// Keeps the Library window beside the front panel window's right edge, and knows whether it is open.
///
/// Every time the Library window opens, its left edge stands `gap` points right of the front panel window's right edge
/// with both tops in line, and it becomes the front panel window's child window, which AppKit moves along whenever its
/// parent moves. The
/// Library window cannot be moved on its own, and a drag on it moves the front panel window and with it both. Where
/// the screen's right edge leaves the Library window no room, the front panel window moves left until it fits. Whether
/// it is open follows the window itself, so closing it with its close button or from the View menu releases the front
/// panel's key as well.
@MainActor
@Observable
public final class LibraryWindowAttachment {
    /// Whether the Library window is open.
    public private(set) var isLibraryOpen = false
    @ObservationIgnored private weak var frontPanelWindow: NSWindow?
    @ObservationIgnored private weak var libraryWindow: NSWindow?
    @ObservationIgnored private var libraryObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var dragStart: DragStart?
    @ObservationIgnored private var isAdjusting = false

    public init() {}
}

extension LibraryWindowAttachment {
    /// The space between the front panel window's right edge and the Library window.
    static let gap: CGFloat = 12

    /// The drag on the Library panel, which moves the front panel window, so the Library window moves along with it.
    var libraryDrag: some Gesture {
        DragGesture()
            .onChanged { drag in
                self.dragFrontPanel(translation: drag.translation, pointer: NSEvent.mouseLocation)
            }
            .onEnded { _ in
                self.dragStart = nil
            }
    }

    /// Takes the window the front panel stands in, and attaches an open Library window to it.
    func frontPanelWindowChanged(_ window: NSWindow?) {
        frontPanelWindow = window
        attachLibrary()
    }

    /// Takes the window the Library panel stands in, or nil once the panel has left it, which closes it for the key.
    func libraryWindowChanged(_ window: NSWindow?) {
        if window !== libraryWindow {
            stopObservingLibrary()
            libraryWindow = window
            if let window {
                window.isMovable = false
                observe(window)
            }
        }
        isLibraryOpen = window != nil
        attachLibrary()
    }

    /// Moves the front panel window so that it follows the pointer from where the drag started.
    ///
    /// The pointer is read in screen coordinates, because the panel's own coordinates move with the window. The drag's
    /// first translation, which a drag gesture reports in the view's coordinates with the y axis pointing down, gives
    /// the point where the pointer went down.
    func dragFrontPanel(translation: CGSize, pointer: NSPoint) {
        guard let frontPanelWindow else {
            return
        }
        let start = dragStart ?? DragStart(
            pointer: NSPoint(x: pointer.x - translation.width, y: pointer.y + translation.height),
            origin: frontPanelWindow.frame.origin
        )
        dragStart = start
        frontPanelWindow.setFrameOrigin(NSPoint(
            x: start.origin.x + pointer.x - start.pointer.x,
            y: start.origin.y + pointer.y - start.pointer.y
        ))
    }
}

private extension LibraryWindowAttachment {
    /// Where a drag on the Library panel started: the pointer and the front panel window's origin, both on the screen.
    struct DragStart {
        let pointer: NSPoint
        let origin: NSPoint
    }

    /// Puts an open Library window beside the front panel window's right edge and attaches it as its child window.
    func attachLibrary() {
        guard
            let frontPanelWindow,
            let libraryWindow,
            isLibraryOpen
        else {
            return
        }
        placeLibrary()
        if libraryWindow.parent !== frontPanelWindow {
            frontPanelWindow.addChildWindow(libraryWindow, ordered: .above)
        }
    }

    func placeLibrary() {
        guard
            let frontPanelWindow,
            let libraryWindow,
            !Self.isBeside(libraryWindow, frontPanelWindow)
        else {
            return
        }
        libraryWindow.setFrameTopLeftPoint(Self.libraryTopLeft(beside: frontPanelWindow.frame))
    }

    /// Where the Library window's top left corner belongs: `gap` points right of the front panel window, level with
    /// its top.
    static func libraryTopLeft(beside frontPanel: NSRect) -> NSPoint {
        NSPoint(x: frontPanel.maxX + gap, y: frontPanel.maxY)
    }

    /// Whether the Library window stands at its place beside the front panel window.
    static func isBeside(_ libraryWindow: NSWindow, _ frontPanelWindow: NSWindow) -> Bool {
        NSPoint(x: libraryWindow.frame.minX, y: libraryWindow.frame.maxY) == libraryTopLeft(beside: frontPanelWindow.frame)
    }

    /// Brings the Library window back beside the front panel window after something other than its parent moved it.
    ///
    /// AppKit pulls a titled window back onto the screen when it orders the window front, and no setter can put a
    /// visible window off the screen again, so where the screen's right edge leaves the Library window no room beside
    /// the front panel window, the front panel window moves left until it fits. Neither window then covers the other,
    /// and the Library window stays in view. A Library window that only followed its parent still stands beside it, so
    /// a drag toward the screen's edge goes where the pointer takes it. Moving the front panel window moves the Library
    /// window along, which reports a move of its own, so the adjustment ignores the moves it makes itself.
    func libraryMoved() {
        guard
            !isAdjusting,
            isLibraryOpen,
            let frontPanelWindow,
            let libraryWindow,
            !Self.isBeside(libraryWindow, frontPanelWindow),
            let screen = libraryWindow.screen ?? frontPanelWindow.screen
        else {
            return
        }
        isAdjusting = true
        defer { isAdjusting = false }
        let frontPanel = frontPanelWindow.frame
        let overhang = frontPanel.maxX + Self.gap + libraryWindow.frame.width - screen.visibleFrame.maxX
        if overhang > 0 {
            frontPanelWindow.setFrameOrigin(NSPoint(x: frontPanel.minX - overhang, y: frontPanel.minY))
        }
        placeLibrary()
    }

    /// Follows the Library window closing, coming back into view, taking a new size, which would move its top, and
    /// moving away from its place. Closing needs no detaching, because AppKit removes a child window from its parent
    /// when it leaves the screen.
    func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        libraryObservers = [
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isLibraryOpen = false
                }
            },
            center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.libraryVisibilityChanged()
                }
            },
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.placeLibrary()
                }
            },
            center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.libraryMoved()
                }
            },
        ]
    }

    func stopObservingLibrary() {
        for observer in libraryObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        libraryObservers = []
    }

    /// A Library window that comes back into view is open again, even where SwiftUI shows the same window once more.
    func libraryVisibilityChanged() {
        guard
            let libraryWindow,
            libraryWindow.occlusionState.contains(.visible),
            !isLibraryOpen
        else {
            return
        }
        isLibraryOpen = true
        attachLibrary()
    }
}
