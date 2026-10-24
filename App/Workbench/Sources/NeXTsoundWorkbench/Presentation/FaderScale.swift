import Foundation
import NeXTsoundCore

extension DSPParameter {
    /// Whether a slider for the parameter gives each decade the same travel. Frequencies, qualities and times span
    /// several decades, while gains and levels are already logarithmic in decibels.
    var usesLogarithmicScale: Bool {
        switch self {
        case .highPassFrequency, .bandFrequency, .bandQuality, .limiterRelease: true
        case .bandGain, .attenuation, .limiterThreshold: false
        }
    }
}

/// How a fader's travel maps onto its parameter's range, with position 0 at the bottom and 1 at the top.
enum FaderScale: Sendable {
    case linear(ClosedRange<Float>)
    case logarithmic(LogarithmicScale)
}

extension FaderScale {
    /// The scale for a parameter's range, logarithmic where the parameter asks for it.
    init(parameter: DSPParameter) {
        if parameter.usesLogarithmicScale, let scale = try? LogarithmicScale(bounds: parameter.bounds) {
            self = .logarithmic(scale)
        } else {
            self = .linear(parameter.bounds)
        }
    }

    /// The position of a value, clamped to the travel.
    func position(for value: Float) -> Double {
        switch self {
        case let .linear(bounds):
            guard
                !value.isNaN,
                bounds.upperBound > bounds.lowerBound
            else {
                return 0
            }
            let clamped = min(max(value, bounds.lowerBound), bounds.upperBound)
            return Double((clamped - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound))
        case let .logarithmic(scale):
            return scale.position(for: value)
        }
    }

    /// The value at a position, clamped to the parameter's range.
    func value(at position: Double) -> Float {
        switch self {
        case let .linear(bounds):
            let clamped = position.isNaN ? 0 : min(max(position, 0), 1)
            return bounds.lowerBound + Float(clamped) * (bounds.upperBound - bounds.lowerBound)
        case let .logarithmic(scale):
            return scale.value(at: position)
        }
    }
}

/// What a fader's value is measured in, which sets how its readout and VoiceOver show it.
enum FaderUnit: Sendable {
    case hertz
    case decibels
    case milliseconds
    case quality
}

extension FaderUnit {
    /// The readout's text, kept compact. It leaves out the unit, because the caption under the fader
    /// names the value, and it writes decimals with a point, as a device's display does.
    func readout(_ value: Float) -> String {
        switch self {
        case .hertz where value >= 10000:
            String(format: "%.0fk", locale: Self.displayLocale, value / 1000)
        case .hertz where value >= 1000:
            String(format: "%.1fk", locale: Self.displayLocale, value / 1000)
        case .hertz, .milliseconds:
            String(format: "%.0f", locale: Self.displayLocale, value)
        case .decibels:
            (value > 0 ? "+" : "") + String(format: "%.1f", locale: Self.displayLocale, value)
        case .quality:
            String(format: "%.2f", locale: Self.displayLocale, value)
        }
    }

    /// The value as VoiceOver reads it, followed by its unit's symbol.
    func spoken(_ value: Float) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0 ... 2)))) \(symbol)"
    }
}

private extension FaderUnit {
    static let displayLocale = Locale(identifier: "en_US_POSIX")

    var symbol: String {
        switch self {
        case .hertz: "Hz"
        case .decibels: "dB"
        case .milliseconds: "ms"
        case .quality: "Q"
        }
    }
}
