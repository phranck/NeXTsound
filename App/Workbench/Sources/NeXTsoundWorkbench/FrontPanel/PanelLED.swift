import SwiftUI

/// An LED that shows a state: dark and sunk while off, cyan with a glow while lit, fading between the two.
struct PanelLED: View {
    nonisolated static let size: CGFloat = 6

    let isLit: Bool
    /// Whether the LED confirms an action, lighting at once and draining away over 900 ms, instead of fading both
    /// ways as a state does.
    var confirms = false
    var color = PanelLEDColor.cyan
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x262626).shadow(.inner(color: .black.opacity(0.7), radius: 0.5, y: 1)))
            Circle()
                .fill(color.lit)
                .shadow(color: color.lit.opacity(0.5), radius: 2)
                .shadow(color: color.lit.opacity(0.2), radius: 6)
                .opacity(isLit ? 1 : 0)
        }
        .frame(width: Self.size, height: Self.size)
        .animation(animation, value: isLit)
        .accessibilityHidden(true)
    }
}

/// The color an LED lights in: the kit's cyan for a state, and amber for a caution that stands until it is resolved.
enum PanelLEDColor {
    case cyan
    case amber

    var lit: Color {
        switch self {
        case .cyan: FrontPanelPalette.cyan
        case .amber: Color(hex: 0xFFB02E)
        }
    }
}

private extension PanelLED {
    var animation: Animation? {
        guard confirms else {
            return FrontPanelMotion.state(reduceMotion: reduceMotion)
        }
        return isLit ? nil : .easeOut(duration: reduceMotion ? 0.3 : 0.9)
    }
}
