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
}
