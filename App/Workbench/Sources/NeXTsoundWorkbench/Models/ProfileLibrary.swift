import Foundation
import NeXTsoundCore

/// The internally managed collection of profiles the workbench edits locally.
public struct ProfileLibrary: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1
    public static let maximumProfiles = 128
    public static let maximumFileBytes = 8 * 1024 * 1024

    public let formatVersion: Int
    public private(set) var revision: UInt64
    public private(set) var profiles: [SoundProfile]
    public private(set) var selectedID: UUID

    public var selectedProfile: SoundProfile {
        profiles.first { $0.id == selectedID } ?? profiles[0]
    }

    public init() {
        let profile = FactoryPreset.flat.makeProfile()
        formatVersion = Self.currentFormatVersion
        revision = 1
        profiles = [profile]
        selectedID = profile.id
    }

    public init(profiles: [SoundProfile], selectedID: UUID, revision: UInt64 = 1) throws {
        formatVersion = Self.currentFormatVersion
        self.revision = revision
        self.profiles = profiles
        self.selectedID = selectedID
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        revision = try container.decode(UInt64.self, forKey: .revision)
        profiles = try container.decode([SoundProfile].self, forKey: .profiles)
        selectedID = try container.decode(UUID.self, forKey: .selectedID)
        try validate()
    }
}

public extension ProfileLibrary {
    func validate() throws {
        guard
            formatVersion == Self.currentFormatVersion,
            revision > 0,
            !profiles.isEmpty,
            profiles.count <= Self.maximumProfiles,
            Set(profiles.map(\.id)).count == profiles.count,
            profiles.contains(where: { $0.id == selectedID })
        else {
            throw ProfileLibraryError.invalidLibrary
        }
        try profiles.forEach { try $0.validate() }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumFileBytes else {
            throw ProfileLibraryError.oversizedFile
        }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumFileBytes else {
            throw ProfileLibraryError.oversizedFile
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    mutating func select(_ identifier: UUID) throws {
        guard profiles.contains(where: { $0.id == identifier }) else {
            throw ProfileLibraryError.invalidLibrary
        }
        guard selectedID != identifier else {
            return
        }
        try advanceRevision()
        selectedID = identifier
    }

    mutating func updateSelected(_ proposed: SoundProfile) throws {
        var file = ProfileFile(profile: selectedProfile)
        try file.edit { $0 = proposed }
        guard file.profile != selectedProfile else {
            return
        }
        try advanceRevision()
        profiles = profiles.map { $0.id == selectedID ? file.profile : $0 }
    }

    mutating func insert(_ profile: SoundProfile) throws {
        try profile.validate()
        if let existing = profiles.first(where: { $0.id == profile.id }) {
            guard existing == profile else {
                throw ProfileLibraryError.duplicateProfile
            }
            try select(profile.id)
            return
        }
        guard profiles.count < Self.maximumProfiles else {
            throw ProfileLibraryError.profileLimit
        }
        try advanceRevision()
        profiles.append(profile)
        selectedID = profile.id
    }

    mutating func removeSelected() throws {
        guard profiles.count > 1 else {
            throw ProfileLibraryError.lastProfile
        }
        try advanceRevision()
        profiles.removeAll { $0.id == selectedID }
        selectedID = profiles[0].id
    }

    /// Reverts to a previous snapshot, used to undo the mutation that followed it.
    mutating func restoreContents(from previous: Self) throws {
        guard profiles != previous.profiles || selectedID != previous.selectedID else {
            return
        }
        var restored = previous
        restored.revision = revision
        try restored.advanceRevision()
        self = restored
    }
}

private extension ProfileLibrary {
    enum CodingKeys: String, CodingKey {
        case formatVersion
        case revision
        case profiles
        case selectedID
    }

    mutating func advanceRevision() throws {
        guard revision < .max else {
            throw ProfileLibraryError.exhaustedRevision
        }
        revision += 1
    }
}

public enum ProfileLibraryError: Error, Equatable, LocalizedError, Sendable {
    case invalidLibrary
    case oversizedFile
    case duplicateProfile
    case profileLimit
    case lastProfile
    case exhaustedRevision

    public var errorDescription: String? {
        switch self {
        case .invalidLibrary: String(
                localized: "The profile library is invalid or uses an unsupported format. The stored file is unchanged."
            )
        case .oversizedFile: String(localized: "The profile file exceeds the local storage limit.")
        case .duplicateProfile: String(localized: "A different version of this profile already exists. Import has not replaced it.")
        case .profileLimit: String(localized: "The profile library is full. Export and remove a profile before adding another.")
        case .lastProfile: String(localized: "Keep at least one profile in the workbench.")
        case .exhaustedRevision: String(localized: "The profile library revision is exhausted.")
        }
    }
}
