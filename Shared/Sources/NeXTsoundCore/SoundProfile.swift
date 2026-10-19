import Foundation

public enum ProfileValidationError: Error, Equatable, Sendable {
    case unsupportedFormat(UInt32)
    case invalidName
    case invalidRevision
    case invalidSpeaker
    case invalidEnclosure
    case invalidModelReference
}

extension ProfileValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(version): String(localized: "Unsupported profile format \(version).")
        case .invalidName: String(localized: "Give the profile a name.")
        case .invalidRevision: String(localized: "The profile revision is invalid or exhausted.")
        case .invalidSpeaker: String(localized: "Check the speaker specifications and their sources.")
        case .invalidEnclosure: String(localized: "Check the enclosure volume and its source.")
        case .invalidModelReference: String(localized: "Check the model reference and SHA-256 digest.")
        }
    }
}

public struct SoundProfile: Codable, Equatable, Identifiable, Sendable {
    public static let currentFormatVersion: UInt32 = 1

    public let formatVersion: UInt32
    public var id: UUID
    public var revision: UInt32
    public var name: String
    public var presetOrigin: String?
    public var settings: DSPSettings
    public var speaker: SpeakerRecord?
    public var enclosure: EnclosureRecord?

    public var deviceSnapshot: DeviceSnapshot {
        DeviceSnapshot(profileID: id, profileRevision: revision, settings: settings)
    }

    public init(id: UUID = UUID(), name: String = "Untitled", settings: DSPSettings = DSPSettings()) {
        formatVersion = Self.currentFormatVersion
        self.id = id
        revision = 1
        self.name = name
        presetOrigin = nil
        self.settings = settings
        speaker = nil
        enclosure = nil
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let incomingVersion = try container.decode(UInt32.self, forKey: .formatVersion)
        guard incomingVersion == Self.currentFormatVersion else {
            throw ProfileValidationError.unsupportedFormat(incomingVersion)
        }
        formatVersion = incomingVersion
        id = try container.decode(UUID.self, forKey: .id)
        revision = try container.decode(UInt32.self, forKey: .revision)
        name = try container.decode(String.self, forKey: .name)
        presetOrigin = try container.decodeIfPresent(String.self, forKey: .presetOrigin)
        settings = try container.decode(DSPSettings.self, forKey: .settings)
        speaker = try container.decodeIfPresent(SpeakerRecord.self, forKey: .speaker)
        enclosure = try container.decodeIfPresent(EnclosureRecord.self, forKey: .enclosure)
        try validate()
    }
}

public extension SoundProfile {
    func validate() throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw ProfileValidationError.unsupportedFormat(formatVersion)
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileValidationError.invalidName
        }
        guard revision > 0 else {
            throw ProfileValidationError.invalidRevision
        }
        try settings.validate()
        try speaker?.validate()
        try enclosure?.validate()
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(id, forKey: .id)
        try container.encode(revision, forKey: .revision)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(presetOrigin, forKey: .presetOrigin)
        try container.encode(settings, forKey: .settings)
        try container.encodeIfPresent(speaker, forKey: .speaker)
        try container.encodeIfPresent(enclosure, forKey: .enclosure)
    }

    mutating func advanceRevision() throws {
        guard revision < .max else {
            throw ProfileValidationError.invalidRevision
        }
        revision += 1
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}

private extension SoundProfile {
    enum CodingKeys: String, CodingKey {
        case formatVersion
        case id
        case revision
        case name
        case presetOrigin
        case settings
        case speaker
        case enclosure
    }
}
