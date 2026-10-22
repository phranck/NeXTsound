import SwiftUI

/// A phosphor color of the front panel's displays.
///
/// Each one has a bright step for text and the curve, a normal step for labels and grid lines, and a ghost step for
/// the unlit dots. The values are the mockup's `--vfd-*` colors.
enum PhosphorTheme: String, CaseIterable, Sendable {
    case blue
    case white
    case amber
}

extension PhosphorTheme {
    /// The glass every display's dots sit behind.
    static let glass = Color(red: 5 / 255, green: 8 / 255, blue: 10 / 255).opacity(0.92)

    /// The step for text and the curve.
    var bright: Color {
        switch self {
        case .blue: Color(hex: 0x7AEBFF)
        case .white: Color(hex: 0xF4F8FF)
        case .amber: Color(hex: 0xFFCF6B)
        }
    }

    /// The step for labels and grid lines.
    var normal: Color {
        switch self {
        case .blue: Color(hex: 0x5FB7C7)
        case .white: Color(hex: 0xCDD6E6)
        case .amber: Color(hex: 0xE0A53A)
        }
    }

    /// The step for the unlit dots.
    var ghost: Color {
        switch self {
        case .blue: Color(hex: 0x1B3438)
        case .white: Color(hex: 0x2A2E38)
        case .amber: Color(hex: 0x3A2A0E)
        }
    }

    /// The color of a tone in this theme.
    func color(for tone: DotMatrixTone) -> Color {
        switch tone {
        case .bright: bright
        case .normal: normal
        }
    }
}

extension Color {
    /// A color from a 24-bit sRGB value, written the way the mockup writes it.
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
