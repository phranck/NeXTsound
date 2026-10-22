import SwiftUI

/// An LED that shows a state: dark and sunk while off, cyan with a glow while lit, fading between the two.
struct PanelLED: View {
    nonisolated static let size: CGFloat = 6

    let isLit: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x262626).shadow(.inner(color: .black.opacity(0.7), radius: 0.5, y: 1)))
            Circle()
                .fill(FrontPanelPalette.cyan)
                .shadow(color: FrontPanelPalette.cyan.opacity(0.5), radius: 2)
                .shadow(color: FrontPanelPalette.cyan.opacity(0.2), radius: 6)
                .opacity(isLit ? 1 : 0)
        }
        .frame(width: Self.size, height: Self.size)
        .animation(FrontPanelMotion.state(reduceMotion: reduceMotion), value: isLit)
        .accessibilityHidden(true)
    }
}
