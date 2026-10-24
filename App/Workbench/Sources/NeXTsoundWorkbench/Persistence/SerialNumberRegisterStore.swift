import Foundation

public protocol SerialNumberRegisterStorage: Sendable {
    func load() async throws -> SerialNumberRegister?
    func save(_ register: SerialNumberRegister) async throws
}

/// Atomic local JSON persistence for the serial-number register, beside the profile library in Application Support.
/// Not device storage.
public actor SerialNumberRegisterStore: SerialNumberRegisterStorage {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }
}

public extension SerialNumberRegisterStore {
    static func standard() throws -> SerialNumberRegisterStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return SerialNumberRegisterStore(fileURL: directory.appendingPathComponent("NeXTsound/serial-numbers.json"))
    }

    /// Nil when no register has been saved yet.
    func load() throws -> SerialNumberRegister? {
        do {
            let data = try AtomicJSONFile.read(fileURL, maximumBytes: SerialNumberRegister.maximumFileBytes)
            return try SerialNumberRegister.decode(data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    func save(_ register: SerialNumberRegister) throws {
        try AtomicJSONFile.write(register.encoded(), to: fileURL)
    }
}
