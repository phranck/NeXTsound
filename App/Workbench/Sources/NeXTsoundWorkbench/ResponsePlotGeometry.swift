import CoreGraphics
import Foundation
import NeXTsoundCore

struct ResponsePlotGeometry: Sendable {
    static let displayLimitDb = 18.0
    let plot: CGRect

    init(size: CGSize) {
        plot = CGRect(x: 42, y: 16, width: max(size.width - 58, 1), height: max(size.height - 48, 1))
    }
}

extension ResponsePlotGeometry {
    func point(frequencyHz: Double, decibels: Double) -> CGPoint {
        let bounds = DSPParameter.bandFrequency.bounds
        let frequency = frequencyHz.isFinite ? min(max(frequencyHz, Double(bounds.lowerBound)), Double(bounds.upperBound))
            : Double(bounds.lowerBound)
        let fraction = log(frequency / Double(bounds.lowerBound)) / log(Double(bounds.upperBound / bounds.lowerBound))
        let limit = Self.displayLimitDb
        let gain = decibels.isFinite ? min(max(decibels, -limit), limit) : 0
        return CGPoint(x: plot.minX + fraction * plot.width, y: plot.minY + (limit - gain) / (2 * limit) * plot.height)
    }
}
