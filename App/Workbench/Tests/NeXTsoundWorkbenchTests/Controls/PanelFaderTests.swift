import NeXTsoundCore
import SwiftUI
import Testing
@testable import NeXTsoundWorkbench

extension RenderingTests {
    struct PanelFaderTests {
        /// Measured in the rendered pixels, Master Volume's 0 dB tick stands at three quarters of the way from the -80 dB
        /// tick at the bottom of the travel to the +12 dB tick at its top, and it alone reaches the fader's outer edge.
        @Test func theTicksSitWhereTheirValuesAre() async throws {
            let ticks = DSPParameter.attenuation.faderTicks()
            let pixels = try await MainActor.run {
                try RenderedPixels(FaderTicks(ticks: ticks).frame(width: PanelFaderMetrics.width, height: PanelFaderMetrics.height))
            }
            let everyTick = Self.tickCenters(in: pixels, column: Int(PanelFaderMetrics.referenceTickLength * 2) - 1)
            let longTicks = Self.tickCenters(in: pixels, column: 1)
            #expect(everyTick.count == ticks.count)
            #expect(longTicks.count == 1)
            let top = try #require(everyTick.first)
            let bottom = try #require(everyTick.last)
            let zeroDecibels = try #require(longTicks.first)
            #expect(abs(zeroDecibels - (bottom - 0.75 * (bottom - top))) < 1)
        }
    }
}

private extension RenderingTests.PanelFaderTests {
    /// The center of every run of lit pixels down `column`, weighted by brightness, in pixel rows from the top.
    static func tickCenters(in pixels: RenderedPixels, column: Int) -> [Double] {
        var centers: [Double] = []
        var weightedRows = 0.0
        var weight = 0.0
        for row in 0 ..< pixels.height {
            let brightness = Double(pixels.pixel(column: column, row: row).red)
            if brightness > 0 {
                weightedRows += (Double(row) + 0.5) * brightness
                weight += brightness
            } else if weight > 0 {
                centers.append(weightedRows / weight)
                weightedRows = 0
                weight = 0
            }
        }
        if weight > 0 {
            centers.append(weightedRows / weight)
        }
        return centers
    }
}
