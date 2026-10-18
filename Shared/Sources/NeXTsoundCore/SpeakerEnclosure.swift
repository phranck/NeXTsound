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
