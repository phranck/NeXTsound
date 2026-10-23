import Foundation
import NeXTsoundCore

public struct ResponsePoint: Equatable, Sendable {
    public let frequencyHz: Double
    public let decibels: Double
}

public struct LogarithmicScale: Sendable {
    public let bounds: ClosedRange<Float>

    public init(bounds: ClosedRange<Float>) throws {
        guard
            bounds.lowerBound.isFinite,
            bounds.upperBound.isFinite,
            bounds.lowerBound > 0,
            bounds.upperBound > bounds.lowerBound
        else {
            throw WorkbenchError.invalidScale
        }
        self.bounds = bounds
    }
}

public extension LogarithmicScale {
    func position(for value: Float) -> Double {
        let clamped = value.isNaN ? bounds.lowerBound : min(max(value, bounds.lowerBound), bounds.upperBound)
        return log(Double(clamped / bounds.lowerBound)) / log(Double(bounds.upperBound / bounds.lowerBound))
    }

    func value(at position: Double) -> Float {
        let clamped = position.isNaN ? 0 : min(max(position, 0), 1)
        let ratio = Double(bounds.upperBound / bounds.lowerBound)
        return min(max(Float(Double(bounds.lowerBound) * pow(ratio, clamped)), bounds.lowerBound), bounds.upperBound)
    }
}

public enum ResponseCurve {}

public extension ResponseCurve {
    static func samples(settings: DSPSettings, count: Int = 161) throws -> [ResponsePoint] {
        guard (2 ... 2048).contains(count) else {
            throw WorkbenchError.invalidSampleCount
        }
        try settings.validate()
        let response = try EQResponse(settings: settings)
        let scale = try LogarithmicScale(bounds: DSPParameter.bandFrequency.bounds)
        return try (0 ..< count).map { index in
            let frequency = Double(scale.value(at: Double(index) / Double(count - 1)))
            return try ResponsePoint(frequencyHz: frequency, decibels: response.decibels(at: frequency))
        }
    }
}
