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

public extension DriverRecord {
    /// The only driver currently in use. Values come from the full parameter table in
    /// `DS-TEBM28C10-4/A revision 1.7` (the already-linked datasheet; an earlier reading of it
    /// missed this table and left most fields nil). Mounting/fit fields stay nil where the
    /// datasheet's own outline drawing does not give them cleanly: the drawing splits overall
    /// depth into front/rear segments without itemizing which is which, and does not label a
    /// mounting hole diameter, so neither is guessed.
    static func tectonicTEBM28C10_4() -> DriverRecord {
        let id = UUID(uuid: (0xD4, 0x71, 0x0E, 0x1C, 0x7E, 0x58, 0x4A, 0x8A, 0x9B, 0x6E, 0x0C, 0x28, 0xC1, 0x04, 0x7A, 0x2D))
        var driver = DriverRecord(id: id, name: "Tectonic Elements TEBM28C10-4")
        driver.manufacturer = "Tectonic Elements"
        driver.model = "TEBM28C10-4"
        driver.origin = .datasheet
        driver.sourceURLs = [
            URL(string: "https://doc.soundimports.nl/pdf/brands/Tectonic%20Elements/TEBM28C10-4.A%20BMR/tebm28c10-4a-spec-sheet.pdf")!,
        ]
        driver.nominalImpedanceOhms = 4
        driver.reOhms = 4.40
        driver.leMillihenries = 0.09
        driver.blTeslaMeters = 2.87
        driver.fsHz = 130
        driver.qts = 0.39
        driver.qes = 0.45
        driver.qms = 2.74
        driver.vasLiters = 0.15
        driver.sdSquareCentimeters = 8.55
        driver.mmsGrams = 1.0
        driver.xmaxMillimeters = 4.0
        driver.frameDiameterMillimeters = 46
        driver.mountingPitchCircleDiameterMillimeters = 48.0
        driver.mountingHoleCount = 4
        driver.ratedPowerWatts = 10
        driver.notes = """
        Datasheet identifies the model as TEBM28C10-4/A; the CAD reference labels it \
        TEBM28C10-4B. The correspondence between this physical unit and either identity is \
        not verified. Fs is typical with plus-or-minus 20% tolerance, not a measured value. \
        The 10 W rating is continuous weighted pink noise per IEC268-5 with a second-order \
        high-pass; no cutoff frequency is specified. The datasheet states maximum coil \
        excursion as 8.0 mm peak-to-peak; xmaxMillimeters holds half of that (4.0 mm one-way) \
        to match this field's one-way convention. Mounting pitch circle diameter (48.0 mm) and \
        hole count (4, read directly from the outline drawing) agree with the independently \
        measured enclosure CAD record's pilot pattern.
        """
        return driver
    }
}
