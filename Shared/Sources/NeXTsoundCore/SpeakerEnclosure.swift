import Foundation

public enum SpecificationOrigin: String, Codable, CaseIterable, Sendable {
    case unknown
    case userProvided
    case datasheet
}

public struct SpeakerRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var manufacturer: String?
    public var model: String?
    public var nominalImpedanceOhms: Double?
    public var ratedPowerWatts: Double?
    public var recommendedHighPassHz: Double?
    public var origin: SpecificationOrigin
    public var sourceURLs: [URL]
    public var notes: String

    public init(id: UUID = UUID(), name: String = "Custom speaker") {
        self.id = id
        self.name = name
        manufacturer = nil
        model = nil
        nominalImpedanceOhms = nil
        ratedPowerWatts = nil
        recommendedHighPassHz = nil
        origin = .unknown
        sourceURLs = []
        notes = ""
    }
}

public extension SpeakerRecord {
    /// Snapshots a driver library entry's identity, electrical/power specs, and provenance into
    /// a profile's speaker record, matching the catalog/snapshot separation: a later edit to the
    /// library entry never changes an already-saved profile.
    init(driver: DriverRecord) {
        id = driver.id
        name = driver.name
        manufacturer = driver.manufacturer
        model = driver.model
        nominalImpedanceOhms = driver.nominalImpedanceOhms
        ratedPowerWatts = driver.ratedPowerWatts
        recommendedHighPassHz = driver.recommendedHighPassHz
        origin = driver.origin
        sourceURLs = driver.sourceURLs
        notes = driver.notes
    }

    func validate() throws {
        let specifications = [nominalImpedanceOhms, ratedPowerWatts, recommendedHighPassHz].compactMap(\.self)
        guard
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            specifications.allSatisfy({ $0.isFinite && $0 > 0 }),
            sourceURLs.allSatisfy({ $0.scheme == "https" || $0.scheme == "http" }),
            origin != .datasheet || !sourceURLs.isEmpty
        else {
            throw ProfileValidationError.invalidSpeaker
        }
    }
}

public enum VolumeOrigin: String, Codable, CaseIterable, Sendable {
    case manual
    case model
    case measured
}

public struct EnclosureVolume: Codable, Equatable, Sendable {
    public var internalLiters: Double
    public var displacementLiters: Double
    public var origin: VolumeOrigin

    public var netLiters: Double {
        internalLiters - displacementLiters
    }

    public init(internalLiters: Double, displacementLiters: Double = 0, origin: VolumeOrigin = .manual) {
        self.internalLiters = internalLiters
        self.displacementLiters = displacementLiters
        self.origin = origin
    }
}

public struct ModelReference: Codable, Equatable, Sendable {
    public var fileName: String
    public var revision: String?
    public var sha256: String?

    public init(fileName: String, revision: String? = nil, sha256: String? = nil) {
        self.fileName = fileName
        self.revision = revision
        self.sha256 = sha256
    }
}

public struct EnclosureRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var volume: EnclosureVolume?
    public var modelReference: ModelReference?
    public var notes: String

    public init(id: UUID = UUID(), name: String = "Enclosure") {
        self.id = id
        self.name = name
        volume = nil
        modelReference = nil
        notes = ""
    }
}

public extension EnclosureRecord {
    /// The one fixed enclosure this product ships. Vb (net internal air volume) comes from
    /// `Documentation/Verification/Enclosure-2026-10-21.json`: the owner modeled the interior
    /// cavity itself as its own solid in Shapr3D and exported it, the driver, and the RP2350
    /// board separately; each STL's volume was computed via the divergence theorem over its
    /// connected components, and Vb is the cavity volume minus driver and board displacement.
    /// Supersedes the 2026-10-18 record, which described an earlier, not yet acoustically
    /// sealed design and is no longer current.
    static func nextSoundBoxMini() -> EnclosureRecord {
        let id = UUID(uuid: (0x6F, 0x1D, 0x4A, 0x2E, 0x9C, 0x05, 0x4F, 0x83, 0xA6, 0x2B, 0x7D, 0x14, 0xE0, 0x58, 0x3C, 0x91))
        var enclosure = EnclosureRecord(id: id, name: "NeXT Sound Box mini")
        enclosure.volume = EnclosureVolume(internalLiters: 0.196018, displacementLiters: 0.017686, origin: .model)
        enclosure.modelReference = ModelReference(
            fileName: "Documentation/Verification/Enclosure-2026-10-21.json",
            sha256: "817a67353801d7e35f8b8e361c59a81ddbc301b90e2628ad99e4ae4ceebf0dc8"
        )
        enclosure.notes = """
        Internal cavity 0.196018 L, minus driver displacement 0.017153 L and RP2350 board \
        assembly displacement 0.000533 L (0.017686 L combined), net Vb = 0.178332 L. The \
        source STL files were temporary chat attachments, already removed from disk when \
        this record was written; their sha256 could not be captured, so the committed \
        provenance JSON's own sha256 is what this reference checks instead.
        """
        return enclosure
    }
}

public extension EnclosureRecord {
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileValidationError.invalidEnclosure
        }
        if let volume {
            guard
                volume.internalLiters.isFinite,
                volume.internalLiters > 0,
                volume.displacementLiters.isFinite,
                volume.displacementLiters >= 0,
                volume.netLiters > 0,
                volume.origin != .model || modelReference != nil
            else {
                throw ProfileValidationError.invalidEnclosure
            }
        }
        if let modelReference {
            guard !modelReference.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProfileValidationError.invalidModelReference
            }
            if let digest = modelReference.sha256 {
                let bytes = Array(digest.utf8)
                guard
                    bytes.count == 64,
                    bytes.allSatisfy({ (48 ... 57).contains($0) || (65 ... 70).contains($0) || (97 ... 102).contains($0) })
                else {
                    throw ProfileValidationError.invalidModelReference
                }
            }
        }
    }
}
