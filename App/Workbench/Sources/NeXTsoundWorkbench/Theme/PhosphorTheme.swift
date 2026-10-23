import SwiftUI

/// A phosphor color of the front panel's displays.
///
/// Each one has a bright step for text and the curve, a normal step for labels, a dim step for the multifunction
/// display's axes, grid lines and scale labels, and a ghost step for the unlit dots. The bright, normal and ghost
/// values are the mockup's `--vfd-*` colors, and the dim step lies between the normal step and the ghost step.
enum PhosphorTheme: String, CaseIterable, Sendable {
    case blue
    case white
    case amber
}

extension PhosphorTheme {
    /// The defaults key of the display color, which the front panel and the Library panel share and keep across
    /// launches.
    static let storageKey = "frontPanelPhosphorTheme"

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

    /// The step for labels.
    var normal: Color {
        Color(hex: normalShade)
    }

    /// The step for the multifunction display's axes, grid lines and scale labels, which recede behind the curve.
    var dim: Color {
        Color(mixing: ghostShade, normalShade, secondShare: Self.dimShare)
    }

    /// The step for the unlit dots.
    var ghost: Color {
        Color(hex: ghostShade)
    }

    /// The color of a tone in this theme.
    func color(for tone: DotMatrixTone) -> Color {
        switch tone {
        case .bright: bright
        case .normal: normal
        }
    }
}

private extension PhosphorTheme {
    /// The share of the normal step in the dim step, whose rest comes from the ghost step.
    static let dimShare = 0.6

    var normalShade: UInt32 {
        switch self {
        case .blue: 0x5FB7C7
        case .white: 0xCDD6E6
        case .amber: 0xE0A53A
        }
    }

    var ghostShade: UInt32 {
        switch self {
        case .blue: 0x1B3438
        case .white: 0x2A2E38
        case .amber: 0x3A2A0E
        }
    }
}

extension EnvironmentValues {
    /// The phosphor color of every display, which the front panel and the Library panel set from the stored choice.
    @Entry var phosphorTheme = PhosphorTheme.blue
}
