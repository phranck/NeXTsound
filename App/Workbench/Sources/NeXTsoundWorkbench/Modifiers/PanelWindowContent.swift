import AppKit
import SwiftUI

extension View {
    /// Makes the view the whole content of a window whose title bar is hidden. The view starts at the window's top
    /// edge, under the bar and the window's buttons. The window takes exactly the view's size. A drag anywhere on the
    /// view moves the window, unless a control takes it.
    func panelWindowContent() -> some View {
        modifier(PanelWindowContent())
    }
}

/// Pulls a panel up under its window's hidden title bar and lets a drag on the panel move the window.
///
/// A window that takes its content's size adds the title bar's safe area to the size the content asks for, even
/// where the content ignores that area. Pulling the panel up by the bar's height makes it ask for that much less, so
/// the window ends where the panel ends. The height comes from the window rather than from the panel's safe area,
/// because the panel leaves the safe area as it moves up, and a safe area read from it would undo the move. Only the
/// drag answers the click that activates the window, so a click into an inactive window never presses one of the
/// panel's keys.
private struct PanelWindowContent: ViewModifier {
    @State private var titleBarHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .allowsWindowActivationEvents(false)
            .padding(.top, -titleBarHeight)
            .background {
                TitleBarReader(height: $titleBarHeight)
                    .frame(width: 0, height: 0)
            }
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents()
    }
}

/// An AppKit view without an area that reads the title bar's height of the window it stands in.
///
/// It takes no room, so an image render, which draws no AppKit view, has nothing to leave out.
private struct TitleBarReader: NSViewRepresentable {
    @Binding var height: CGFloat

    func makeNSView(context _: Context) -> TitleBarReadingView {
        let view = TitleBarReadingView()
        view.report = { height = $0 }
        return view
    }

    func updateNSView(_ view: TitleBarReadingView, context _: Context) {
        view.report = { height = $0 }
    }
}

/// Reports its window's title bar height, which is the window's height less the rectangle its content may use
/// unobscured, once it stands in the window.
private final class TitleBarReadingView: NSView {
    var report: (CGFloat) -> Void = { _ in }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            return
        }
        let height = window.frame.height - window.contentLayoutRect.height
        // The view moves into the window while SwiftUI updates the panel, which must not change its state.
        Task { [report] in
            report(height)
        }
    }
}
