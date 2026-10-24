import SwiftUI

extension View {
    /// Puts a display's glass behind the view, with a light edge along its top and left and a dark one along its
    /// bottom and right, as every display in the mockup has.
    func vfdGlass(cornerRadius: CGFloat) -> some View {
        background(
            PhosphorTheme.glass
                .shadow(.inner(color: .white.opacity(0.03), radius: 0, x: 1, y: 1))
                .shadow(.inner(color: .black.opacity(0.6), radius: 0, x: -1, y: -1)),
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
    }

    /// Lays a faint highlight one point under the view's rounded outline, where a frame's lower edge catches the
    /// light.
    func frameHighlight(cornerRadius: CGFloat, opacity: Double) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.white.opacity(opacity))
                .offset(y: 1)
        }
    }
}
