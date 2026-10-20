import Foundation
import Testing
@testable import NeXTsoundCore

struct ClosedBoxAlignmentTests {
    @Test func referenceDriverInTheFixedEnclosureYieldsBesselAlignment() throws {
        let alignment = try ClosedBoxAlignment(
            resonantFrequencyHz: 130,
            totalQ: 0.39,
            equivalentComplianceVolumeLiters: 0.15,
            netVolumeLiters: 0.178332
        )
        #expect(abs(alignment.complianceRatio - 0.841_127_784_132_965_5) < 0.000_000_1)
        #expect(abs(alignment.cornerFrequencyHz - 176.394_613) < 0.000_1)
        #expect(abs(alignment.totalQ - 0.529_183_839) < 0.000_000_1)
        #expect(alignment.qualitativeAlignment == .bessel)
    }

    @Test func driverConvenienceInitializerReadsFsQtsVasFromTheRecord() throws {
        let alignment = try ClosedBoxAlignment(driver: .tectonicTEBM28C10_4(), netVolumeLiters: 0.178332)
        #expect(abs(alignment.cornerFrequencyHz - 176.394_613) < 0.000_1)
        #expect(abs(alignment.totalQ - 0.529_183_839) < 0.000_000_1)
    }

    @Test func zeroComplianceRatioLeavesFcAndQtcAtTheFreeAirValues() throws {
        // A vanishingly small Vas relative to Vb approaches an infinite, unenclosed box: Fc -> Fs, Qtc -> Qts.
        let alignment = try ClosedBoxAlignment(
            resonantFrequencyHz: 100,
            totalQ: 0.5,
            equivalentComplianceVolumeLiters: 0.000_001,
            netVolumeLiters: 100
        )
        #expect(abs(alignment.cornerFrequencyHz - 100) < 0.01)
        #expect(abs(alignment.totalQ - 0.5) < 0.000_1)
    }

    @Test func aSmallBoxRelativeToVasRaisesFcAndQtcSubstantially() throws {
        // Vas == Vb doubles the compliance ratio's (1 + alpha) term, i.e. Fc and Qtc both scale by sqrt(2).
        let alignment = try ClosedBoxAlignment(
            resonantFrequencyHz: 100,
            totalQ: 0.4,
            equivalentComplianceVolumeLiters: 1,
            netVolumeLiters: 1
        )
        #expect(abs(alignment.cornerFrequencyHz - 100 * 2.0.squareRoot()) < 0.000_1)
        #expect(abs(alignment.totalQ - 0.4 * 2.0.squareRoot()) < 0.000_1)
        #expect(alignment.qualitativeAlignment == .bessel)
    }

    @Test(arguments: [
        (0.3, ClosedBoxQualitativeAlignment.overdamped),
        (0.55, .bessel),
        (0.707, .butterworth),
        (0.9, .chebyshev),
        (1.2, .underdamped),
    ])
    func classifiesTotalQIntoTheNamedAlignment(totalQ: Double, expected: ClosedBoxQualitativeAlignment) throws {
        // alpha = 0 isolates totalQ == qts, so the classification boundary can be tested directly.
        let alignment = try ClosedBoxAlignment(
            resonantFrequencyHz: 100,
            totalQ: totalQ,
            equivalentComplianceVolumeLiters: 0.000_000_1,
            netVolumeLiters: 1
        )
        #expect(alignment.qualitativeAlignment == expected)
    }

    @Test func missingResonantFrequencyIsRejectedByName() {
        #expect(throws: ClosedBoxAlignmentError.missingResonantFrequency) {
            try ClosedBoxAlignment(resonantFrequencyHz: nil, totalQ: 0.4, equivalentComplianceVolumeLiters: 0.1, netVolumeLiters: 0.2)
        }
    }

    @Test func missingTotalQIsRejectedByName() {
        #expect(throws: ClosedBoxAlignmentError.missingTotalQ) {
            try ClosedBoxAlignment(resonantFrequencyHz: 100, totalQ: nil, equivalentComplianceVolumeLiters: 0.1, netVolumeLiters: 0.2)
        }
    }

    @Test func missingEquivalentComplianceVolumeIsRejectedByName() {
        #expect(throws: ClosedBoxAlignmentError.missingEquivalentComplianceVolume) {
            try ClosedBoxAlignment(resonantFrequencyHz: 100, totalQ: 0.4, equivalentComplianceVolumeLiters: nil, netVolumeLiters: 0.2)
        }
    }

    @Test func nonFiniteOrNonPositiveNetVolumeIsRejected() {
        #expect(throws: ClosedBoxAlignmentError.invalidNetVolume) {
            try ClosedBoxAlignment(resonantFrequencyHz: 100, totalQ: 0.4, equivalentComplianceVolumeLiters: 0.1, netVolumeLiters: 0)
        }
        #expect(throws: ClosedBoxAlignmentError.invalidNetVolume) {
            try ClosedBoxAlignment(resonantFrequencyHz: 100, totalQ: 0.4, equivalentComplianceVolumeLiters: 0.1, netVolumeLiters: .nan)
        }
    }

    @Test func driverWithoutQtsOrVasCannotProduceAnAlignment() {
        // tectonicTEBM28C10_4B has fsHz and qts but no vasLiters (datasheet does not state it).
        #expect(throws: ClosedBoxAlignmentError.missingEquivalentComplianceVolume) {
            try ClosedBoxAlignment(driver: .tectonicTEBM28C10_4B(), netVolumeLiters: 0.178332)
        }
    }
}
