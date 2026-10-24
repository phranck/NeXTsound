import SwiftUI

/// A phosphor color of the front panel's displays.
///
/// Each one has a peak step for what stands out from the curve, a bright step for text and the curve, a normal step for
/// labels, a dim step for the multifunction display's axes, grid lines and scale labels, and a ghost step for the unlit
/// dots. The bright, normal and ghost values are the mockup's `--vfd-*` colors. The peak step lies between the bright
/// step and white, and the dim step between the normal step and the ghost step.
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

    /// The step for what stands out from the curve, such as the selected band's marker.
    var peak: Color {
        Color(mixing: brightShade, Self.whiteShade, secondShare: Self.peakShare)
    }

    /// The step for text and the curve.
    var bright: Color {
        Color(hex: brightShade)
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
    /// The share of white in the peak step, whose rest comes from the bright step.
    static let peakShare = 0.6
    /// White, which the peak step mixes into the bright step.
    static let whiteShade: UInt32 = 0xFFFFFF

    var brightShade: UInt32 {
        switch self {
        case .blue: 0x7AEBFF
        case .white: 0xF4F8FF
        case .amber: 0xFFCF6B
        }
    }

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
