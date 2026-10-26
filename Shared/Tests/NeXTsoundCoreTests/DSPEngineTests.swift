import Foundation
import Testing
@testable import NeXTsoundCore

struct DSPEngineTests {
    /// With a flat, unmuted profile at full volume, the engine passes the average of both channels, as the board does.
    @Test func aFlatProfilePassesTheAverageOfBothChannels() throws {
        var engine = try DSPEngine(settings: Self.flat())
        let output = try Self.peak(of: &engine, left: 0.5, right: 0.3)
        #expect(abs(output - 0.4) < 0.01)
    }

    /// The profile's attenuation lowers the signal by its value.
    @Test func theAttenuationLowersTheSignalByItsValue() throws {
        var settings = Self.flat()
        settings.attenuationDb = -20
        var engine = try DSPEngine(settings: settings)
        let output = try Self.peak(of: &engine, left: 0.5, right: 0.5)
        #expect(abs(20 * log10(output / 0.5) + 20) < 0.1)
    }

    /// A muted profile sends silence.
    @Test func aMutedProfileSendsSilence() throws {
        var settings = Self.flat()
        settings.isMuted = true
        var engine = try DSPEngine(settings: settings)
        #expect(try Self.peak(of: &engine, left: 0.5, right: 0.5) == 0)
    }

    /// New settings take effect once their crossfade has run, and a second change during the crossfade is refused.
    @Test func newSettingsTakeEffectAfterTheirCrossfade() throws {
        var engine = try DSPEngine(settings: Self.flat())
        _ = try Self.peak(of: &engine, left: 0.5, right: 0.5)
        var quieter = Self.flat()
        quieter.attenuationDb = -12
        #expect(try engine.apply(quieter))
        #expect(try !engine.apply(Self.flat()))
        let output = try Self.peak(of: &engine, left: 0.5, right: 0.5)
        #expect(abs(20 * log10(output / 0.5) + 12) < 0.1)
    }

    /// Any number of frames passes in blocks the C engine accepts, one mono sample per stereo frame.
    @Test func anyLengthPassesInBlocks() throws {
        var engine = try DSPEngine(settings: Self.flat())
        var mono: [Float] = []
        #expect(engine.process(Array(repeating: 0.25, count: 2 * (DSPEngine.blockFrames * 3 + 7)), into: &mono))
        #expect(mono.count == DSPEngine.blockFrames * 3 + 7)
    }

    @Test func settingsOutsideTheBoundsAreRejected() {
        var settings = Self.flat()
        settings.attenuationDb = .nan
        #expect(throws: WireError.self) { try DSPEngine(settings: settings) }
    }
}

private extension DSPEngineTests {
    /// A profile that leaves the signal as it is: no high-pass, flat bands, no attenuation, not muted.
    static func flat() -> DSPSettings {
        var settings = DSPSettings()
        settings.highPassEnabled = false
        settings.attenuationDb = 0
        settings.limiterThresholdDb = -1
        settings.isMuted = false
        for index in settings.bands.indices {
            settings.bands[index].gainDb = 0
        }
        return settings
    }

    /// The peak of the engine's output for a 1 kHz sine of `left` and `right` amplitude, measured over its second
    /// half, after the crossfade into the engine's settings has run.
    static func peak(of engine: inout DSPEngine, left: Float, right: Float) throws -> Float {
        let frames = 4800
        var stereo: [Float] = []
        for frame in 0 ..< frames {
            let phase = Float(sin(2 * Double.pi * 1000 * Double(frame) / 48000))
            stereo += [left * phase, right * phase]
        }
        var mono: [Float] = []
        try #require(engine.process(stereo, into: &mono))
        return mono[(frames / 2)...].map(abs).max() ?? 0
    }
}
