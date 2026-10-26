import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct FaderScaleTests {
    @Test func aLinearScaleMapsTheRangeOntoTheTravel() {
        let scale = FaderScale(parameter: .bandGain)
        #expect(scale.position(for: -12) == 0)
        #expect(scale.position(for: 0) == 0.5)
        #expect(scale.position(for: 12) == 1)
        #expect(scale.value(at: 0.25) == -6)
    }

    @Test func aLogarithmicScaleGivesEachDecadeTheSameTravel() {
        let scale = FaderScale(parameter: .bandFrequency)
        #expect(abs(scale.position(for: 200) - 1.0 / 3) < 1e-6)
        #expect(abs(scale.position(for: 2000) - 2.0 / 3) < 1e-6)
        #expect(abs(scale.value(at: 0.5) - 632.4555) < 0.01)
        #expect(scale.value(at: 1) == 20000)
    }

    @Test func bothScalesClampToTheRange() {
        for parameter in [DSPParameter.bandGain, .bandFrequency] {
            let scale = FaderScale(parameter: parameter)
            #expect(scale.position(for: parameter.bounds.upperBound * 10) == 1)
            #expect(scale.value(at: -1) == parameter.bounds.lowerBound)
            #expect(scale.value(at: 2) == parameter.bounds.upperBound)
            #expect(scale.position(for: .nan) == 0)
        }
    }

    /// Master Volume's fader law puts each of its points on its share of the travel, 0 dB at three quarters, and an
    /// arrow key's step near 0 dB moves it by about half a decibel.
    @Test func theVolumeFadersLawPutsZeroDecibelsAtThreeQuartersOfTheTravel() throws {
        let scale = FaderScale(parameter: .attenuation)
        let law = try #require(DSPParameter.attenuation.faderLaw)
        for point in law {
            #expect(abs(scale.position(for: point.value) - point.position) < 1e-9)
            #expect(abs(scale.value(at: point.position) - point.value) < 1e-4)
        }
        #expect(abs(scale.position(for: 0) - 0.75) < 1e-9)
        #expect(scale.value(at: 0) == DSPParameter.attenuation.bounds.lowerBound)
        #expect(scale.value(at: 1) == DSPParameter.attenuation.bounds.upperBound)
        let step = scale.value(at: 0.75) - scale.value(at: 0.74)
        #expect(step > 0.3 && step < 0.7)
    }

    /// Along the law, every step up the travel raises the value, and position and value round-trip.
    @Test func theVolumeFadersLawOnlyRisesAndRoundTrips() {
        let scale = FaderScale(parameter: .attenuation)
        var previous = -Float.infinity
        for index in 0 ... 1000 {
            let position = Double(index) / 1000
            let value = scale.value(at: position)
            #expect(value > previous)
            #expect(abs(scale.position(for: value) - position) < 1e-6)
            previous = value
        }
    }

    /// On a board whose range ends at 0 dB, the travel ends there, and below it the law keeps its shape.
    @Test func aNarrowerRangeEndsTheTravelAtItsTop() {
        let scale = FaderScale(parameter: .attenuation, range: -80 ... 0)
        #expect(scale.value(at: 1) == 0)
        #expect(scale.value(at: 0) == -80)
        #expect(abs(scale.position(for: -12) - 0.55 / 0.75) < 1e-9)
    }

    @Test func readoutsAreCompactAndWriteDecimalsWithAPoint() {
        #expect(FaderUnit.hertz.readout(176) == "176")
        #expect(FaderUnit.hertz.readout(1500) == "1.5k")
        #expect(FaderUnit.hertz.readout(12000) == "12k")
        #expect(FaderUnit.decibels.readout(5.5) == "+5.5")
        #expect(FaderUnit.decibels.readout(-24) == "-24.0")
        #expect(FaderUnit.decibels.readout(0) == "0.0")
        #expect(FaderUnit.milliseconds.readout(120) == "120")
        #expect(FaderUnit.quality.readout(0.53) == "0.53")
    }

    /// Every parameter's ticks stand inside its range, rise along the travel, and sit where its fader's scale places
    /// their values, so a tick and the cap agree on where a value is.
    @Test func everyTickStandsWhereItsFadersScalePlacesItsValue() {
        for parameter in DSPParameter.allCases {
            let scale = FaderScale(parameter: parameter)
            let ticks = parameter.faderTicks()
            #expect(ticks.count == parameter.tickValues.count)
            #expect(parameter.tickValues.allSatisfy(parameter.bounds.contains))
            for (tick, value) in zip(ticks, parameter.tickValues) {
                #expect(tick.position == scale.position(for: value))
            }
            #expect(zip(ticks, ticks.dropFirst()).allSatisfy { $0.position < $1.position })
        }
    }

    /// Master Volume's and the band gain's 0 dB ticks are their reference ticks, at three quarters and at half of the
    /// travel, and the other faders have none.
    @Test func zeroDecibelsIsTheReferenceTickOfTheGainFaders() {
        #expect(DSPParameter.attenuation.faderTicks().filter(\.isReference).map(\.position) == [0.75])
        #expect(DSPParameter.bandGain.faderTicks().filter(\.isReference).map(\.position) == [0.5])
        for parameter in DSPParameter.allCases where parameter != .attenuation && parameter != .bandGain {
            let hasReferenceTick = parameter.faderTicks().contains { $0.isReference }
            #expect(!hasReferenceTick)
        }
    }

    /// The band frequency's ticks mark the decades a reader looks for.
    @Test func theBandFrequencyHasTicksAtEveryDecade() {
        for decade: Float in [100, 1000, 10000] {
            #expect(DSPParameter.bandFrequency.tickValues.contains(decade))
        }
    }

    /// On a board whose range ends at 0 dB, the ticks above it are not drawn, and the 0 dB tick marks the top.
    @Test func aNarrowerRangeDropsTheTicksBeyondIt() {
        let ticks = DSPParameter.attenuation.faderTicks(range: -80 ... 0)
        #expect(ticks.count == DSPParameter.attenuation.tickValues.count(where: { $0 <= 0 }))
        #expect(ticks.last == FaderTick(position: 1, isReference: true))
    }
}
