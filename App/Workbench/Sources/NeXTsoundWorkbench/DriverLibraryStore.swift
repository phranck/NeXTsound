import Foundation
import NeXTsoundCore

public protocol DriverLibraryStorage: Sendable {
    func load() async throws -> DriverLibrary?
    func save(_ library: DriverLibrary) async throws
}

/// Atomic local JSON persistence for the driver model library. Not device storage.
public actor DriverLibraryStore: DriverLibraryStorage {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }
}

public extension DriverLibraryStore {
    static func standard() -> DriverLibraryStore {
        DriverLibraryStore(fileURL: DriverStorageLocation.resolveRootDirectory().appendingPathComponent("drivers.json"))
    }

    func load() throws -> DriverLibrary? {
        do {
            let data = try AtomicJSONFile.read(fileURL, maximumBytes: DriverLibrary.maximumFileBytes)
            return try DriverLibrary.decode(data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        } catch AtomicJSONFileError.oversizedFile {
            throw DriverLibraryError.oversizedFile
        }
    }

    func save(_ library: DriverLibrary) throws {
        let data = try library.encoded()
        try AtomicJSONFile.write(data, to: fileURL)
    }
}
