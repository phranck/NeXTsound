import AppKit
import Observation
import SwiftUI

/// Keeps the Library window beside the front panel window's right edge, and knows whether it is open.
///
/// Every time the Library window opens, its left edge stands `gap` points right of the front panel window's right edge
/// with both tops in line, and it becomes the front panel window's child window, which AppKit moves along whenever its
/// parent moves. The
/// Library window cannot be moved on its own, and a drag on it moves the front panel window and with it both. Whether
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
            let libraryWindow
        else {
            return
        }
        let frontPanel = frontPanelWindow.frame
        libraryWindow.setFrameTopLeftPoint(NSPoint(x: frontPanel.maxX + Self.gap, y: frontPanel.maxY))
    }

    /// Follows the Library window closing, coming back into view, and taking a new size, which would move its top.
    /// Closing needs no detaching, because AppKit removes a child window from its parent when it leaves the screen.
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
