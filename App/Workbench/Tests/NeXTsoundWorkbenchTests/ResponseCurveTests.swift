import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct ResponseCurveTests {
    @Test func logarithmicControlsHaveExactEndsAndRoundTrip() throws {
        let scale = try LogarithmicScale(bounds: DSPParameter.bandFrequency.bounds)
        #expect(scale.position(for: 20) == 0)
        #expect(scale.position(for: 20000) == 1)
        #expect(scale.value(at: 0) == 20)
        #expect(scale.value(at: 1) == 20000)
        for frequency: Float in [20, 100, 1000, 10000, 20000] {
            #expect(abs(scale.value(at: scale.position(for: frequency)) - frequency) < 0.01)
        }
        #expect(scale.value(at: -1) == 20)
        #expect(scale.value(at: 2) == 20000)
    }

    @Test func nonfiniteDisplayCoordinatesCannotProduceNaNSliderValues() throws {
        let scale = try LogarithmicScale(bounds: DSPParameter.bandFrequency.bounds)
        #expect(scale.position(for: .nan) == 0)
        #expect(scale.value(at: .nan) == 20)
        #expect(scale.value(at: .infinity) == 20000)
        #expect(scale.value(at: -.infinity) == 20)
    }

    @Test func invalidLogarithmicBoundsAreRejected() {
        #expect(throws: WorkbenchError.invalidScale) { try LogarithmicScale(bounds: 0 ... 20) }
        #expect(throws: WorkbenchError.invalidScale) { try LogarithmicScale(bounds: 20 ... 20) }
        #expect(throws: WorkbenchError.invalidScale) { try LogarithmicScale(bounds: 20 ... .infinity) }
    }

    @Test func sampledResponseUsesTheSharedAnalyticalResponse() throws {
        let settings = FactoryPreset.warm.makeProfile().settings
        let reference = try EQResponse(settings: settings)
        let points = try ResponseCurve.samples(settings: settings)
        #expect(points.count == 161)
        #expect(points.first?.frequencyHz == 20)
        #expect(points.last?.frequencyHz == 20000)
        for point in points {
            #expect(try abs(point.decibels - (reference.decibels(at: point.frequencyHz))) < 1e-10)
        }
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.frequencyHz < $1.frequencyHz })
    }

    @Test func previewExcludesMuteAttenuationAndLimiter() throws {
        var settings = DSPSettings()
        let reference = try ResponseCurve.samples(settings: settings)
        settings.attenuationDb = -80
        settings.isMuted = false
        settings.limiterThresholdDb = -36
        settings.limiterReleaseMs = 2000
        #expect(try ResponseCurve.samples(settings: settings) == reference)
    }

    @Test func invalidResponseRequestsAreRejected() {
        #expect(throws: WorkbenchError.invalidSampleCount) { try ResponseCurve.samples(settings: DSPSettings(), count: 1) }
        #expect(throws: WorkbenchError.invalidSampleCount) { try ResponseCurve.samples(settings: DSPSettings(), count: 2049) }
        var settings = DSPSettings()
        settings.bands = []
        #expect(throws: (any Error).self) { try ResponseCurve.samples(settings: settings) }
    }
}
