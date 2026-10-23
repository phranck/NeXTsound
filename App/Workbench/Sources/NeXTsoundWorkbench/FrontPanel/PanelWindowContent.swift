import SwiftUI

extension View {
    /// Makes the view the whole content of a window whose title bar is hidden. The view starts at the window's top
    /// edge, under the bar and the window's buttons. The window takes exactly the view's size. A drag anywhere on the
    /// view moves the window, unless a control takes it.
    func panelWindowContent() -> some View {
        modifier(PanelWindowContent(drag: WindowDragGesture()))
    }

    /// Makes the view the whole content of a window whose title bar is hidden, as `panelWindowContent()` does, with
    /// `drag` taking a drag on the view in place of the window's own drag.
    func panelWindowContent(drag: some Gesture) -> some View {
        modifier(PanelWindowContent(drag: drag))
    }
}

/// Pulls a panel up under its window's hidden title bar and lets a drag on the panel move a window.
///
/// A window that takes its content's size adds the title bar's safe area to the size the content asks for, even
/// where the content ignores that area. Pulling the panel up by that inset makes it ask for that much less, so the
/// window ends where the panel ends. The background measures the inset, because it stays inside the safe area while
/// the panel moves up out of it. Only the drag answers the click that activates the window, so a click into an
/// inactive window never presses one of the panel's keys.
private struct PanelWindowContent<Drag: Gesture>: ViewModifier {
    let drag: Drag
    @State private var titleBarHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .allowsWindowActivationEvents(false)
            .padding(.top, -titleBarHeight)
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.safeAreaInsets.top
                    } action: { height in
                        titleBarHeight = height
                    }
            }
            .gesture(drag)
            .allowsWindowActivationEvents()
    }
}
