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

public extension View {
    /// Tells the panels in the view that their window opens with a titled window's title bar, hidden, so each panel
    /// stands under the bar from the window's first frame on. A scene with a hidden title bar sets it on its content.
    func opensInTitledWindow() -> some View {
        environment(\.openingTitleBarHeight, PanelWindowContent.titledWindowTitleBarHeight)
    }
}

extension EnvironmentValues {
    /// The height of the title bar that a panel's window opens with, which is 0 where no window holds the panel, as
    /// in a render.
    @Entry var openingTitleBarHeight: CGFloat = 0
}

/// Pulls a panel up under its window's hidden title bar and lets a drag on the panel move the window.
///
/// A window that takes its content's size adds the title bar's safe area to the size the content asks for, even
/// where the content ignores that area. Pulling the panel up by the bar's height makes it ask for that much less, so
/// the window ends where the panel ends. The panel starts from the height its scene says the window opens with, so
/// the window's first frame already shows it in place, and the window confirms the height once the panel stands in
/// it. The height never comes from the panel's safe area, because the panel leaves the safe area as it moves up, and
/// a safe area read from it would undo the move. Only the drag answers the click that activates the window, so a
/// click into an inactive window never presses one of the panel's keys.
private struct PanelWindowContent: ViewModifier {
    @Environment(\.openingTitleBarHeight) private var openingTitleBarHeight
    @State private var windowTitleBarHeight: CGFloat?

    func body(content: Content) -> some View {
        content
            .allowsWindowActivationEvents(false)
            .padding(.top, -(windowTitleBarHeight ?? openingTitleBarHeight))
            .background {
                TitleBarReader(height: $windowTitleBarHeight)
                    .frame(width: 0, height: 0)
            }
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents()
    }
}

@MainActor
extension PanelWindowContent {
    /// The height of the title bar that AppKit gives a titled window around its content.
    static var titledWindowTitleBarHeight: CGFloat {
        let content = NSRect(x: 0, y: 0, width: 100, height: 100)
        return NSWindow.frameRect(forContentRect: content, styleMask: .titled).height - content.height
    }
}

/// An AppKit view without an area that reads the title bar's height of the window it stands in.
///
/// It takes no room, so an image render, which draws no AppKit view, has nothing to leave out.
private struct TitleBarReader: NSViewRepresentable {
    @Binding var height: CGFloat?

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
    var report: (CGFloat?) -> Void = { _ in }

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
