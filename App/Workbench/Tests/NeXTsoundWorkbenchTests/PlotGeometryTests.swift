import CoreGraphics
import Testing
@testable import NeXTsoundWorkbench

struct PlotGeometryTests {
    @Test func graphCoordinatesStayInsideTheirPlot() {
        for width: Double in [320, 540, 900] {
            let geometry = ResponsePlotGeometry(size: CGSize(width: width, height: 230))
            let limit = ResponsePlotGeometry.displayLimitDb
            let low = geometry.point(frequencyHz: 20, decibels: limit)
            let high = geometry.point(frequencyHz: 20000, decibels: -limit)
            #expect(low == CGPoint(x: geometry.plot.minX, y: geometry.plot.minY))
            #expect(high == CGPoint(x: geometry.plot.maxX, y: geometry.plot.maxY))
            for frequency: Double in [-1, 20, 1000, 20000, .infinity, .nan] {
                let point = geometry.point(frequencyHz: frequency, decibels: .nan)
                #expect(point.x.isFinite && point.y.isFinite)
                #expect(point.x >= geometry.plot.minX && point.x <= geometry.plot.maxX)
                #expect(point.y >= geometry.plot.minY && point.y <= geometry.plot.maxY)
            }
        }
    }

    @Test func extremeGainClipsOnlyTheDisplayCoordinate() {
        let geometry = ResponsePlotGeometry(size: CGSize(width: 540, height: 230))
        #expect(geometry.point(frequencyHz: 1000, decibels: 100).y == geometry.plot.minY)
        #expect(geometry.point(frequencyHz: 1000, decibels: -100).y == geometry.plot.maxY)
    }
}
