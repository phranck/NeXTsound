import AppKit
import SwiftUI

/// Reports the window a view stands in whenever it changes, and nil once the view has left its window.
///
/// It takes no room, because an image render draws a placeholder over the area of every AppKit view. It reports once
/// the move into a window has finished, so whoever listens can order the window around without interrupting AppKit.
struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context _: Context) -> WindowReaderView {
        WindowReaderView(onChange: onChange)
    }

    func updateNSView(_ view: WindowReaderView, context _: Context) {
        view.onChange = onChange
    }
}

/// The AppKit view behind `WindowReader`.
final class WindowReaderView: NSView {
    var onChange: (NSWindow?) -> Void

    init(onChange: @escaping (NSWindow?) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            onChange(window)
        }
    }
}
