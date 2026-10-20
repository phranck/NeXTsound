import Foundation

public enum ClosedBoxAlignmentError: Error, Equatable, Sendable {
    case missingResonantFrequency
    case missingTotalQ
    case missingEquivalentComplianceVolume
    case invalidNetVolume
}

extension ClosedBoxAlignmentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingResonantFrequency: String(localized: "The driver's free-air resonant frequency (Fs) is required.")
        case .missingTotalQ: String(localized: "The driver's total Q (Qts) is required.")
        case .missingEquivalentComplianceVolume: String(localized: "The driver's equivalent compliance volume (Vas) is required.")
        case .invalidNetVolume: String(
                localized: "The enclosure's net internal air volume (Vb) must be a positive, finite number of liters."
            )
        }
    }
}

/// Small's own alignment names, by total Q (Qtc). Boundaries follow the commonly published
/// alignment chart; they are a naming convention, not a physical threshold.
public enum ClosedBoxQualitativeAlignment: String, Codable, CaseIterable, Sendable {
    case overdamped
    case bessel
    case butterworth
    case chebyshev
    case underdamped
}

/// A deterministic closed-box (sealed enclosure) Thiele/Small alignment, computed from a
/// driver's free-air parameters and the enclosure's net internal air volume (Vb). This is the
/// driver-in-box acoustic high-pass response itself (second order, corner frequency Fc, total
/// Q Qtc) produced by the mechanical/acoustic system, not the firmware's electronic high-pass
/// filter: that one only ever implements a fixed Q of 1/sqrt(2) at a chosen `highPassHz` (see
/// `dsp.c`), independent of whatever the box's own natural alignment is.
public struct ClosedBoxAlignment: Equatable, Sendable {
    /// Alpha: the ratio of the driver's equivalent compliance volume to the box's net volume.
    public let complianceRatio: Double
    /// Fc: the corner frequency of the driver-in-box acoustic high-pass response.
    public let cornerFrequencyHz: Double
    /// Qtc: the total Q of the driver-in-box acoustic high-pass response.
    public let totalQ: Double
    public let qualitativeAlignment: ClosedBoxQualitativeAlignment

    public init(
        resonantFrequencyHz fsHz: Double?,
        totalQ qts: Double?,
        equivalentComplianceVolumeLiters vasLiters: Double?,
        netVolumeLiters vbLiters: Double
    ) throws {
        guard
            let fsHz,
            fsHz.isFinite,
            fsHz > 0
        else {
            throw ClosedBoxAlignmentError.missingResonantFrequency
        }
        guard
            let qts,
            qts.isFinite,
            qts > 0
        else {
            throw ClosedBoxAlignmentError.missingTotalQ
        }
        guard
            let vasLiters,
            vasLiters.isFinite,
            vasLiters > 0
        else {
            throw ClosedBoxAlignmentError.missingEquivalentComplianceVolume
        }
        guard
            vbLiters.isFinite,
            vbLiters > 0
        else {
            throw ClosedBoxAlignmentError.invalidNetVolume
        }
        let alpha = vasLiters / vbLiters
        let growth = (1 + alpha).squareRoot()
        complianceRatio = alpha
        cornerFrequencyHz = fsHz * growth
        totalQ = qts * growth
        qualitativeAlignment = Self.classify(totalQ: totalQ)
    }

    private static func classify(totalQ: Double) -> ClosedBoxQualitativeAlignment {
        switch totalQ {
        case ..<0.50: .overdamped
        case 0.50 ..< 0.60: .bessel
        case 0.60 ..< 0.75: .butterworth
        case 0.75 ..< 1.10: .chebyshev
        default: .underdamped
        }
    }
}

public extension ClosedBoxAlignment {
    /// Convenience initializer reading Fs, Qts, and Vas directly from a driver record.
    init(driver: DriverRecord, netVolumeLiters vbLiters: Double) throws {
        try self.init(
            resonantFrequencyHz: driver.fsHz,
            totalQ: driver.qts,
            equivalentComplianceVolumeLiters: driver.vasLiters,
            netVolumeLiters: vbLiters
        )
    }
}
