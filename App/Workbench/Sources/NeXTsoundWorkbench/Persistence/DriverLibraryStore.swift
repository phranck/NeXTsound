import Foundation
import NeXTsoundCore

public protocol DriverLibraryStorage: Sendable {
    func load() async throws -> DriverLibrary?
    func save(_ library: DriverLibrary) async throws
}

/// Atomic local JSON persistence for the driver model library. Not device storage.
public actor DriverLibraryStore: DriverLibraryStorage {
    public let fileURL: URL
    private var hasLoaded = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }
}

public extension DriverLibraryStore {
    static func standard() throws -> DriverLibraryStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return DriverLibraryStore(fileURL: directory.appendingPathComponent("NeXTsound/drivers.json"))
    }

    func load() throws -> DriverLibrary? {
        // A corrupt or oversized file must not become a write-enabled default library: the owner
        // researched its drivers by hand, so a later save() is refused until a load succeeds.
        hasLoaded = false
        do {
            let data = try AtomicJSONFile.read(fileURL, maximumBytes: DriverLibrary.maximumFileBytes)
            let library = try DriverLibrary.decode(data)
            hasLoaded = true
            return library
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            hasLoaded = true
            return nil
        } catch AtomicJSONFileError.oversizedFile {
            throw DriverLibraryError.oversizedFile
        }
    }

    func save(_ library: DriverLibrary) throws {
        guard hasLoaded else {
            throw DriverLibraryError.invalidLibrary
        }
        let data = try library.encoded()
        try AtomicJSONFile.write(data, to: fileURL)
    }
}
