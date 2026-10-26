import Testing
@testable import NeXTsoundCore

struct DSPSettingsLimitTests {
    /// A value beyond a board's reported range moves to its nearest end, and a value inside stays as it is.
    @Test func valuesBeyondABoardsRangeMoveToItsEnds() {
        var settings = DSPSettings()
        settings.attenuationDb = 6
        settings.limiterThresholdDb = -2
        settings.bands[1].gainDb = 9
        let ranges: [DSPParameter: ClosedRange<Float>] = [.attenuation: -80 ... 0, .bandGain: -6 ... 6]
        let limited = settings.limited(to: ranges)
        #expect(limited.attenuationDb == 0)
        #expect(limited.bands[1].gainDb == 6)
        #expect(limited.limiterThresholdDb == -2)
        #expect(limited.bands[0] == settings.bands[0])
    }

    /// Settings inside every range the shared bounds give stay unchanged.
    @Test func settingsInsideTheSharedBoundsStayUnchanged() {
        var settings = DSPSettings()
        settings.attenuationDb = 12
        let ranges = Dictionary(uniqueKeysWithValues: DSPParameter.allCases.map { ($0, $0.bounds) })
        #expect(settings.limited(to: ranges) == settings)
    }
}
