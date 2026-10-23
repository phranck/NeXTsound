import SwiftUI

extension View {
    /// Lets the view take the keyboard's focus, which `isFocused` tracks, without the system's focus ring, as every
    /// control on the panels takes it.
    func panelFocus(_ isFocused: FocusState<Bool>.Binding) -> some View {
        focusable()
            .focused(isFocused)
            .focusEffectDisabled()
    }
}
