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
/// a safe area read from it would undo the move.
///
/// A drag that no control takes moves the window with the pointer. The panel moves the window itself, because
/// SwiftUI's `WindowDragGesture` on this panel starts and ends at once without moving the window. Only the drag
/// answers the click that activates the window, so a click into an inactive window never presses one of the panel's
/// keys.
private struct PanelWindowContent: ViewModifier {
    @Environment(\.openingTitleBarHeight) private var openingTitleBarHeight
    @State private var windowTitleBarHeight: CGFloat?
    @State private var mover = PanelWindowMover()

    func body(content: Content) -> some View {
        content
            .allowsWindowActivationEvents(false)
            .padding(.top, -(windowTitleBarHeight ?? openingTitleBarHeight))
            .background {
                PanelWindowReader(titleBarHeight: $windowTitleBarHeight, mover: mover)
                    .frame(width: 0, height: 0)
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        mover.follow(pointer: NSEvent.mouseLocation, translation: drag.translation)
                    }
                    .onEnded { _ in
                        mover.endDrag()
                    }
            )
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

/// Moves a panel's window along with the pointer while a drag on the panel lasts.
///
/// It follows the pointer on the screen rather than the drag's own position, because the drag measures in the panel,
/// which moves along with the window.
@MainActor
final class PanelWindowMover {
    /// The window the panel stands in.
    weak var window: NSWindow?
    /// The window's origin and the pointer's position on the screen where the drag began.
    private var start: (origin: NSPoint, pointer: NSPoint)?

    /// Places the window so it has moved as far as the pointer since the drag began.
    ///
    /// - Parameters:
    ///   - pointer: The pointer's position on the screen, whose y axis points up.
    ///   - translation: How far the drag has moved in the panel, whose y axis points down. On the drag's first call it
    ///     places the drag's beginning on the screen.
    func follow(pointer: NSPoint, translation: CGSize) {
        guard let window else {
            return
        }
        let start = start ?? (
            origin: window.frame.origin,
            pointer: NSPoint(x: pointer.x - translation.width, y: pointer.y + translation.height)
        )
        self.start = start
        window.setFrameOrigin(NSPoint(x: start.origin.x + pointer.x - start.pointer.x, y: start.origin.y + pointer.y - start.pointer.y))
    }

    /// Ends the drag, so the next one starts from where the window stands then.
    func endDrag() {
        start = nil
    }
}

/// An AppKit view without an area that reads the window it stands in: the window for the mover, and the height of
/// its title bar.
///
/// It takes no room, so an image render, which draws no AppKit view, has nothing to leave out.
private struct PanelWindowReader: NSViewRepresentable {
    @Binding var titleBarHeight: CGFloat?
    let mover: PanelWindowMover

    func makeNSView(context _: Context) -> PanelWindowReadingView {
        let view = PanelWindowReadingView()
        view.report = report
        return view
    }

    func updateNSView(_ view: PanelWindowReadingView, context _: Context) {
        view.report = report
    }

    /// Hands the window to the mover and takes the title bar's height from it, which is the window's height less the
    /// rectangle its content may use unobscured.
    func report(_ window: NSWindow) {
        mover.window = window
        titleBarHeight = window.frame.height - window.contentLayoutRect.height
    }
}

/// Reports its window once it stands in one.
private final class PanelWindowReadingView: NSView {
    var report: (NSWindow) -> Void = { _ in }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            return
        }
        // The view moves into the window while SwiftUI updates the panel, which must not change its state.
        Task { [report] in
            report(window)
        }
    }
}
