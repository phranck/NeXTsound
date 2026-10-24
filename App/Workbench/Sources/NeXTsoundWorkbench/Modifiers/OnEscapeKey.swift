import SwiftUI

extension View {
    /// Runs `action` when Escape is pressed while the view's window is the key window, whether a view in it has the
    /// focus or not.
    ///
    /// An invisible button takes the key, because a key handler on a view answers only while that view has the focus,
    /// and a panel without a text field or a control to focus would never receive it. The button takes no room and
    /// draws nothing, so a render shows no trace of it.
    func onEscapeKey(perform action: @escaping () -> Void) -> some View {
        background {
            Button(action: action) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }
}
