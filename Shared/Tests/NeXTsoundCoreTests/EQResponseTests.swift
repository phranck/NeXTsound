import Foundation
import Testing
@testable import NeXTsoundCore

struct EQResponseTests {
    @Test func peakingResponseUsesTheFirmwareCoefficients() throws {
        var settings = DSPSettings()
        settings.bands[2].gainDb = 6
        let response = try EQResponse(settings: settings)
        #expect(try abs(response.decibels(at: 1000) - 6) < 0.001)
    }

    @Test func previewExcludesMuteAttenuationAndNonlinearLimiting() throws {
        var settings = DSPSettings()
        settings.bands[2].gainDb = -6
        let first = try EQResponse(settings: settings)
        settings.isMuted.toggle()
        settings.attenuationDb = -80
        settings.limiterThresholdDb = -36
        settings.limiterReleaseMs = 2000
        let second = try EQResponse(settings: settings)
        #expect(try first.decibels(at: 1000) == second.decibels(at: 1000))
    }

    @Test func highPassHasTheButterworthCutoffResponse() throws {
        var settings = DSPSettings()
        settings.highPassEnabled = true
        settings.highPassHz = 100
        let response = try EQResponse(settings: settings)
        #expect(try abs(response.decibels(at: 100) + 3.0103) < 0.02)
    }

    @Test(arguments: [0.0, -1, 24000, Double.infinity, Double.nan])
    func rejectsInvalidFrequencies(_ frequency: Double) throws {
        let response = try EQResponse(settings: DSPSettings())
        #expect(throws: WireError.self) { try response.decibels(at: frequency) }
    }

    @Test func rejectsInvalidSettings() {
        var settings = DSPSettings()
        settings.highPassHz = .nan
        #expect(throws: WireError.self) { try EQResponse(settings: settings) }
    }
}
