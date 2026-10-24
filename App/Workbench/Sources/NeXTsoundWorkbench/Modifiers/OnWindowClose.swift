import AppKit
import SwiftUI

public extension View {
    /// Runs `action` when the window the view stands in is about to close, whether its close button, Command-W or code
    /// closes it.
    func onWindowClose(perform action: @escaping () -> Void) -> some View {
        background {
            WindowCloseObserver(action: action)
                .frame(width: 0, height: 0)
        }
    }
}

/// An AppKit view without an area that runs an action when the window it stands in is about to close.
///
/// It takes no room, so an image render, which draws no AppKit view, has nothing to leave out.
private struct WindowCloseObserver: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context _: Context) -> WindowCloseObservingView {
        let view = WindowCloseObservingView()
        view.action = action
        return view
    }

    func updateNSView(_ view: WindowCloseObservingView, context _: Context) {
        view.action = action
    }
}

/// Observes its window's `willCloseNotification` from the moment it stands in the window until it leaves it.
private final class WindowCloseObservingView: NSView {
    var action: () -> Void = {}
    private var observation: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observation {
            NotificationCenter.default.removeObserver(observation)
        }
        observation = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.action()
                }
            }
        }
    }
}
