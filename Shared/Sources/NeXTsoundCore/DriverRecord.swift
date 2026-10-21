import Foundation

public enum DriverParameter: String, CaseIterable, Sendable {
    case nominalImpedance
    case dcResistance
    case voiceCoilInductance
    case forceFactor
    case resonantFrequency
    case qts
    case qes
    case qms
    case vas
    case effectiveArea
    case mms
    case xmax
    case frameDiameter
    case mountingPitchCircleDiameter
    case mountingHoleCount
    case mountingHoleDiameter
    case rearDepth
    case frontProtrusion
    case ratedPower
    case recommendedHighPass
}

public enum DriverValidationError: Error, Equatable, Sendable {
    case missingName
    case invalidValue(DriverParameter)
    case invalidSourceURL
    case missingDatasheetSource
}

extension DriverValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingName: String(localized: "Give the driver model a name.")
        case let .invalidValue(parameter): String(localized: "Check the \(parameter.rawValue) value.")
        case .invalidSourceURL: String(localized: "Source URLs must be http or https links.")
        case .missingDatasheetSource: String(localized: "A datasheet origin needs at least one source URL.")
        }
    }
}

/// A driver model entry the owner maintains by hand; copied into a profile's `SpeakerRecord`
/// rather than referenced live, matching the existing catalog/snapshot separation.
public struct DriverRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var manufacturer: String?
    public var model: String?
    public var origin: SpecificationOrigin
    public var sourceURLs: [URL]
    public var notes: String

    public var nominalImpedanceOhms: Double?
    public var reOhms: Double?
    public var leMillihenries: Double?
    public var blTeslaMeters: Double?

    public var fsHz: Double?
    public var qts: Double?
    public var qes: Double?
    public var qms: Double?
    public var vasLiters: Double?

    public var sdSquareCentimeters: Double?
    public var mmsGrams: Double?
    public var xmaxMillimeters: Double?

    public var frameDiameterMillimeters: Double?
    public var mountingPitchCircleDiameterMillimeters: Double?
    public var mountingHoleCount: Int?
    public var mountingHoleDiameterMillimeters: Double?
    public var rearDepthMillimeters: Double?
    public var frontProtrusionMillimeters: Double?

    public var ratedPowerWatts: Double?
    public var recommendedHighPassHz: Double?

    public init(id: UUID = UUID(), name: String = "Custom driver") {
        self.id = id
        self.name = name
        manufacturer = nil
        model = nil
        origin = .unknown
        sourceURLs = []
        notes = ""
        nominalImpedanceOhms = nil
        reOhms = nil
        leMillihenries = nil
        blTeslaMeters = nil
        fsHz = nil
        qts = nil
        qes = nil
        qms = nil
        vasLiters = nil
        sdSquareCentimeters = nil
        mmsGrams = nil
        xmaxMillimeters = nil
        frameDiameterMillimeters = nil
        mountingPitchCircleDiameterMillimeters = nil
        mountingHoleCount = nil
        mountingHoleDiameterMillimeters = nil
        rearDepthMillimeters = nil
        frontProtrusionMillimeters = nil
        ratedPowerWatts = nil
        recommendedHighPassHz = nil
    }
}

public extension DriverRecord {
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DriverValidationError.missingName
        }
        guard sourceURLs.allSatisfy({ $0.scheme == "https" || $0.scheme == "http" }) else {
            throw DriverValidationError.invalidSourceURL
        }
        guard origin != .datasheet || !sourceURLs.isEmpty else {
            throw DriverValidationError.missingDatasheetSource
        }
        let doubleParameters: [(Double?, DriverParameter)] = [
            (nominalImpedanceOhms, .nominalImpedance),
            (reOhms, .dcResistance),
            (leMillihenries, .voiceCoilInductance),
            (blTeslaMeters, .forceFactor),
            (fsHz, .resonantFrequency),
            (qts, .qts),
            (qes, .qes),
            (qms, .qms),
            (vasLiters, .vas),
            (sdSquareCentimeters, .effectiveArea),
            (mmsGrams, .mms),
            (xmaxMillimeters, .xmax),
            (frameDiameterMillimeters, .frameDiameter),
            (mountingPitchCircleDiameterMillimeters, .mountingPitchCircleDiameter),
            (mountingHoleDiameterMillimeters, .mountingHoleDiameter),
            (rearDepthMillimeters, .rearDepth),
            (frontProtrusionMillimeters, .frontProtrusion),
            (ratedPowerWatts, .ratedPower),
            (recommendedHighPassHz, .recommendedHighPass),
        ]
        for (value, parameter) in doubleParameters {
            if let value, !(value.isFinite && value > 0) {
                throw DriverValidationError.invalidValue(parameter)
            }
        }
        if let mountingHoleCount, mountingHoleCount <= 0 {
            throw DriverValidationError.invalidValue(.mountingHoleCount)
        }
    }
}

// The pre-researched driver candidates (DriverLibrary.knownCandidates) live in
// DriverCatalog.swift, kept separate so this file stays focused on the type itself.
