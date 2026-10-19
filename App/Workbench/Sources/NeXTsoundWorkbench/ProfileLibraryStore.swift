import Foundation
import NeXTsoundCore

public protocol ProfileLibraryStorage: Sendable {
    func load() async throws -> ProfileLibrary?
    func save(_ library: ProfileLibrary) async throws
}

/// Atomic local JSON persistence for the profile library. Not device storage.
public actor ProfileLibraryStore: ProfileLibraryStorage {
    public let fileURL: URL
    private var hasLoaded = false
    private var storedLibrary: ProfileLibrary?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }
}

public extension ProfileLibraryStore {
    static func standard() throws -> ProfileLibraryStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return ProfileLibraryStore(fileURL: directory.appendingPathComponent("NeXTsound/profiles.json"))
    }

    func load() throws -> ProfileLibrary? {
        do {
            let data = try Self.readLimited(fileURL)
            let library = try ProfileLibrary.decode(data)
            storedLibrary = library
            hasLoaded = true
            return library
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            storedLibrary = nil
            hasLoaded = true
            return nil
        } catch {
            // A corrupt or oversized file must not become a write-enabled empty slate:
            // a later save() has to be refused until a load recovers or replaces it.
            hasLoaded = false
            throw error
        }
    }

    func save(_ library: ProfileLibrary) throws {
        guard hasLoaded else {
            throw ProfileLibraryError.invalidLibrary
        }
        let data = try library.encoded()
        if let storedLibrary {
            guard library.revision >= storedLibrary.revision else {
                return
            }
            guard library.revision != storedLibrary.revision || library == storedLibrary else {
                throw ProfileLibraryError.invalidLibrary
            }
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        storedLibrary = library
    }

    static func importedProfile(at url: URL) throws -> SoundProfile {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try SoundProfile.decode(readLimited(url))
    }
}

private extension ProfileLibraryStore {
    static func readLimited(_ url: URL) throws -> Data {
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard properties.isRegularFile == true else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard
            let size = properties.fileSize,
            size <= ProfileLibrary.maximumFileBytes
        else {
            throw ProfileLibraryError.oversizedFile
        }
        let data = try Data(contentsOf: url)
        guard data.count <= ProfileLibrary.maximumFileBytes else {
            throw ProfileLibraryError.oversizedFile
        }
        return data
    }
}
