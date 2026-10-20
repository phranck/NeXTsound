import Foundation

public enum DriverLibraryError: Error, Equatable, LocalizedError, Sendable {
    case invalidLibrary
    case oversizedFile
    case duplicateDriver
    case driverLimit
    case lastDriver
    case driverNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidLibrary: String(
                localized: "The driver library is invalid or uses an unsupported format. The stored file is unchanged."
            )
        case .oversizedFile: String(localized: "The driver library file exceeds the local storage limit.")
        case .duplicateDriver: String(localized: "A different version of this driver model already exists.")
        case .driverLimit: String(localized: "The driver library is full. Remove a driver model before adding another.")
        case .lastDriver: String(localized: "Keep at least one driver model in the library.")
        case .driverNotFound: String(localized: "That driver model no longer exists.")
        }
    }
}

/// The owner-maintained collection of candidate driver models, independent of any one sound
/// profile; a profile copies the fields of a selected entry into its own `SpeakerRecord`
/// snapshot rather than referencing this library live.
public struct DriverLibrary: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1
    public static let maximumDrivers = 64
    public static let maximumFileBytes = 2 * 1024 * 1024

    public let formatVersion: Int
    public private(set) var drivers: [DriverRecord]

    /// Candidate full-range drivers the owner has researched and may want pre-populated;
    /// `DriverLibraryModel` merges any of these not already present (by id) into an existing
    /// persisted library on load, so the catalog grows as new candidates are added here.
    public static let knownCandidates: [DriverRecord] = [
        .tectonicTEBM28C10_4(),
        .tectonicTEBM28C10_4B(),
        .tectonicTEBM28C10_4BE(),
        .daytonAudioCE41N4(),
        .visatonFR58_4(),
    ]

    public init() {
        formatVersion = Self.currentFormatVersion
        drivers = Self.knownCandidates
    }

    public init(drivers: [DriverRecord]) throws {
        formatVersion = Self.currentFormatVersion
        self.drivers = drivers
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        drivers = try container.decode([DriverRecord].self, forKey: .drivers)
        try validate()
    }
}

public extension DriverLibrary {
    func validate() throws {
        guard
            formatVersion == Self.currentFormatVersion,
            !drivers.isEmpty,
            drivers.count <= Self.maximumDrivers,
            Set(drivers.map(\.id)).count == drivers.count
        else {
            throw DriverLibraryError.invalidLibrary
        }
        try drivers.forEach { try $0.validate() }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumFileBytes else {
            throw DriverLibraryError.oversizedFile
        }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumFileBytes else {
            throw DriverLibraryError.oversizedFile
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    mutating func insert(_ driver: DriverRecord) throws {
        try driver.validate()
        guard !drivers.contains(where: { $0.id == driver.id }) else {
            throw DriverLibraryError.duplicateDriver
        }
        guard drivers.count < Self.maximumDrivers else {
            throw DriverLibraryError.driverLimit
        }
        drivers.append(driver)
    }

    mutating func update(_ driver: DriverRecord) throws {
        try driver.validate()
        guard let index = drivers.firstIndex(where: { $0.id == driver.id }) else {
            throw DriverLibraryError.driverNotFound
        }
        drivers[index] = driver
    }

    mutating func remove(_ identifier: UUID) throws {
        guard drivers.contains(where: { $0.id == identifier }) else {
            throw DriverLibraryError.driverNotFound
        }
        guard drivers.count > 1 else {
            throw DriverLibraryError.lastDriver
        }
        drivers.removeAll { $0.id == identifier }
    }
}

private extension DriverLibrary {
    enum CodingKeys: String, CodingKey {
        case formatVersion
        case drivers
    }
}
