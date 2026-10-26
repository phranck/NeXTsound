import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct SpectrumAnalyzerTests {
    /// The bands are sixth octaves around 1 kHz, each starting where the one below it ends, all inside the curve's
    /// frequency range.
    @Test func theSpectrumBandsTileTheCurvesRangeInSixthOctaves() throws {
        let spectrumBands = SpectrumBand.all
        let range = DSPParameter.bandFrequency.bounds
        #expect(spectrumBands.count == 59)
        #expect(spectrumBands.contains { abs($0.centerHz - 1000) < 1e-9 })
        #expect(try #require(spectrumBands.first).lowerHz >= Double(range.lowerBound))
        #expect(try #require(spectrumBands.last).upperHz <= Double(range.upperBound))
        for (lower, upper) in zip(spectrumBands, spectrumBands.dropFirst()) {
            #expect(abs(lower.upperHz - upper.lowerHz) < 1e-9)
            #expect(abs(upper.centerHz / lower.centerHz - pow(2, 1.0 / 6)) < 1e-12)
        }
    }

    /// A full-scale sine reads 0 dB below full scale on the band that holds it, and nothing two octaves away once the
    /// bands that its onset lit have fallen.
    @Test func aFullScaleSineReadsZeroDecibelsOnItsBand() throws {
        let analyzer = try SpectrumAnalyzer(sampleRate: Self.sampleRate)
        let levels = try #require(analyzer.append(Self.sine(hertz: 1000, amplitude: 1, seconds: 2)))
        #expect(try abs(Self.level(of: levels, atHz: 1000)) < 1)
        #expect(try Self.level(of: levels, atHz: 250) < -60)
        #expect(try Self.level(of: levels, atHz: 4000) < -60)
    }

    /// A sine at half of full scale reads 6 dB lower than one at full scale.
    @Test func aSineAtHalfScaleReadsSixDecibelsLower() throws {
        let analyzer = try SpectrumAnalyzer(sampleRate: Self.sampleRate)
        let levels = try #require(analyzer.append(Self.sine(hertz: 3000, amplitude: 0.5, seconds: 0.5)))
        #expect(try abs(Self.level(of: levels, atHz: 3000) + 20 * log10(2)) < 1)
    }

    /// Silence leaves every band on the analyzer's floor.
    @Test func silenceStaysOnTheFloor() throws {
        let analyzer = try SpectrumAnalyzer(sampleRate: Self.sampleRate)
        let levels = try #require(analyzer.append(Array(repeating: 0, count: Int(Self.sampleRate / 2))))
        #expect(levels.decibels.allSatisfy { $0 == SpectrumAnalyzer.floorDecibels })
    }

    /// The analyzer reports new levels as often as `updatesPerSecond` says, and nothing between two updates.
    @Test func theLevelsUpdateAtTheUpdateRate() throws {
        let analyzer = try SpectrumAnalyzer(sampleRate: Self.sampleRate)
        let hop = Int(Self.sampleRate / SpectrumAnalyzer.updatesPerSecond)
        #expect(analyzer.append(Array(repeating: 0, count: hop - 1)) == nil)
        #expect(analyzer.append([0]) != nil)
        #expect(analyzer.append(Array(repeating: 0, count: hop - 1)) == nil)
    }

    /// A band rises to a louder measurement at once and falls toward a quieter one at the fall rate, never below it.
    @Test func aBandRisesAtOnceAndFallsAtTheFallRate() {
        let fall = SpectrumAnalyzer.fallDecibelsPerSecond
        #expect(SpectrumAnalyzer.level(from: -40, toward: -10, after: 0.1) == -10)
        #expect(abs(SpectrumAnalyzer.level(from: -10, toward: -80, after: 0.1) - (-10 - fall / 10)) < 1e-4)
        #expect(SpectrumAnalyzer.level(from: -10, toward: -12, after: 1) == -12)
    }

    @Test func anUnusableSampleRateIsRejected() {
        #expect(throws: SpectrumError.invalidSampleRate) { try SpectrumAnalyzer(sampleRate: 0) }
        #expect(throws: SpectrumError.invalidSampleRate) { try SpectrumAnalyzer(sampleRate: .nan) }
    }
}

private extension SpectrumAnalyzerTests {
    static let sampleRate = 48000.0

    static func sine(hertz: Double, amplitude: Float, seconds: Double) -> [Float] {
        (0 ..< Int(seconds * sampleRate)).map { index in
            amplitude * Float(sin(2 * Double.pi * hertz * Double(index) / sampleRate))
        }
    }

    /// The level of the band whose edges hold `hertz`.
    static func level(of levels: SpectrumLevels, atHz hertz: Double) throws -> Float {
        let index = try #require(SpectrumBand.all.firstIndex { $0.lowerHz <= hertz && hertz < $0.upperHz })
        return levels.decibels[index]
    }
}
