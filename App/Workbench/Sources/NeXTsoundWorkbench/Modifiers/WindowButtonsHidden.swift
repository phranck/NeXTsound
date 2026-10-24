import AppKit
import SwiftUI

extension View {
    /// Hides the close, minimize and zoom buttons of the view's window, so a window whose title bar is hidden shows
    /// nothing of that bar. The window keeps its buttons, only hidden, so Command-W still closes it.
    func windowButtonsHidden() -> some View {
        background {
            WindowButtonsHider()
                .frame(width: 0, height: 0)
        }
    }
}

/// An AppKit view without an area that hides the standard buttons of the window it stands in.
///
/// The window keeps its hidden title bar rather than taking the plain style, because a plain window is borderless and
/// has no close button, and Command-W only sounds the alert for a window without one. The view takes no room, so an
/// image render, which draws no AppKit view, has nothing to leave out.
private struct WindowButtonsHider: NSViewRepresentable {
    func makeNSView(context _: Context) -> WindowButtonsHidingView {
        WindowButtonsHidingView()
    }

    func updateNSView(_: WindowButtonsHidingView, context _: Context) {}
}

/// Hides its window's standard buttons as soon as it stands in a window. A hidden button stays hidden when the
/// window's style changes.
private final class WindowButtonsHidingView: NSView {
    private static let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for button in Self.buttons {
            window?.standardWindowButton(button)?.isHidden = true
        }
    }
}
