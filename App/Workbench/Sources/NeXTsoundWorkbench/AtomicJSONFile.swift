import Foundation

/// Bounded, atomic local JSON file access shared by every actor-based library store
/// (`ProfileLibraryStore`, `DriverLibraryStore`). Not device storage.
enum AtomicJSONFile {
    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard properties.isRegularFile == true else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard
            let size = properties.fileSize,
            size <= maximumBytes
        else {
            throw AtomicJSONFileError.oversizedFile
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes else {
            throw AtomicJSONFileError.oversizedFile
        }
        return data
    }

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

enum AtomicJSONFileError: Error, Equatable {
    case oversizedFile
}
