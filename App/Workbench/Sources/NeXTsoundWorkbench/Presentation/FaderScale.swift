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

    /// The fader law a parameter's fader follows instead of a linear or logarithmic scale, from the bottom of the
    /// travel to its top, or nil for a parameter without one. Master Volume's spends most of its travel near 0 dB and
    /// less toward silence, as a mixing console's fader does, so 0 dB sits at three quarters of the travel.
    var faderLaw: [FaderLawPoint]? {
        guard self == .attenuation else {
            return nil
        }
        return [
            FaderLawPoint(position: 0, value: bounds.lowerBound),
            FaderLawPoint(position: 0.10, value: -60),
            FaderLawPoint(position: 0.25, value: -40),
            FaderLawPoint(position: 0.40, value: -24),
            FaderLawPoint(position: 0.55, value: -12),
            FaderLawPoint(position: 0.75, value: 0),
            FaderLawPoint(position: 1, value: bounds.upperBound),
        ]
    }
}

/// A point of a fader law: a share of the travel, and the value that falls on it.
struct FaderLawPoint: Equatable, Sendable {
    let position: Double
    let value: Float
}

/// How a fader's travel maps onto its parameter's range, with position 0 at the bottom and 1 at the top.
enum FaderScale: Sendable {
    case linear(ClosedRange<Float>)
    case logarithmic(LogarithmicScale)
    /// A fader law's points, rising along the travel, with the values between two points interpolated linearly.
    case law([FaderLawPoint])
}

extension FaderScale {
    /// The scale for a parameter over `range`, or over the parameter's whole range without one: its fader law where it
    /// has one, cut to `range` and stretched over the whole travel, and otherwise logarithmic where the parameter asks
    /// for it.
    init(parameter: DSPParameter, range: ClosedRange<Float>? = nil) {
        let bounds = range ?? parameter.bounds
        if let law = parameter.faderLaw {
            self = .law(Self.law(law, within: bounds))
        } else if parameter.usesLogarithmicScale, let scale = try? LogarithmicScale(bounds: bounds) {
            self = .logarithmic(scale)
        } else {
            self = .linear(bounds)
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
        case let .law(points):
            return Self.position(for: value, along: points)
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
        case let .law(points):
            return Self.value(at: position, along: points)
        }
    }
}

private extension FaderScale {
    /// The law's points inside `bounds`, with a point at each end of `bounds`, and the positions stretched so the ends
    /// of `bounds` meet the ends of the travel. A board with a narrower range thereby keeps the law's shape below its
    /// top.
    static func law(_ points: [FaderLawPoint], within bounds: ClosedRange<Float>) -> [FaderLawPoint] {
        let lower = position(for: bounds.lowerBound, along: points)
        let upper = position(for: bounds.upperBound, along: points)
        guard upper > lower else {
            return points
        }
        let bottom = FaderLawPoint(position: lower, value: bounds.lowerBound)
        let top = FaderLawPoint(position: upper, value: bounds.upperBound)
        let inner = points.filter { $0.value > bounds.lowerBound && $0.value < bounds.upperBound }
        return ([bottom] + inner + [top]).map { point in
            FaderLawPoint(position: (point.position - lower) / (upper - lower), value: point.value)
        }
    }

    /// The position of `value` along the law, interpolated between the two points around it and clamped to the law.
    static func position(for value: Float, along points: [FaderLawPoint]) -> Double {
        guard
            let first = points.first,
            let last = points.last,
            !value.isNaN
        else {
            return 0
        }
        let clamped = min(max(value, first.value), last.value)
        for (lower, upper) in zip(points, points.dropFirst()) where clamped <= upper.value {
            let share = Double((clamped - lower.value) / (upper.value - lower.value))
            return lower.position + share * (upper.position - lower.position)
        }
        return last.position
    }

    /// The value at `position` along the law, interpolated between the two points around it and clamped to the law.
    static func value(at position: Double, along points: [FaderLawPoint]) -> Float {
        guard
            let first = points.first,
            let last = points.last
        else {
            return 0
        }
        let clamped = position.isNaN ? first.position : min(max(position, first.position), last.position)
        for (lower, upper) in zip(points, points.dropFirst()) where clamped <= upper.position {
            let share = (clamped - lower.position) / (upper.position - lower.position)
            return lower.value + Float(share) * (upper.value - lower.value)
        }
        return last.value
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
