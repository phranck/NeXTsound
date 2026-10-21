import Foundation
import NeXTsoundCore

public enum DriverAssetStoreError: Error, Equatable, Sendable {
    case missingFileExtension
    case copyFailed
}

extension DriverAssetStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingFileExtension: String(localized: "The chosen file has no file extension.")
        case .copyFailed: String(localized: "The file could not be imported.")
        }
    }
}

/// Owner-imported per-driver assets (images, 3D models), stored alongside the driver library
/// so they sync through the same iCloud container. Resolves a stored asset name against the
/// imported copy first, then against the app's own bundled defaults (the reference driver's
/// shipped 3D model), so a bundled default keeps working until the owner replaces it.
public struct DriverAssetStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }
}

public extension DriverAssetStore {
    static func standard() -> DriverAssetStore {
        DriverAssetStore(directory: DriverStorageLocation.resolveRootDirectory().appendingPathComponent("Assets", isDirectory: true))
    }

    func url(forAsset name: String) -> URL? {
        let imported = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: imported.path) {
            return imported
        }
        return Bundle.module.url(forResource: name, withExtension: nil)
    }

    /// Copies the file at `sourceURL` into the asset store under a name stable for `driverID`,
    /// and returns that name for storage in `DriverRecord.model3DAssetName`/`imageAssetName`.
    func importFile(at sourceURL: URL, forDriver driverID: UUID, role: String) throws -> String {
        let extensionName = sourceURL.pathExtension
        guard !extensionName.isEmpty else {
            throw DriverAssetStoreError.missingFileExtension
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "\(driverID.uuidString)-\(role).\(extensionName)"
        let destination = directory.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            throw DriverAssetStoreError.copyFailed
        }
        return filename
    }

    func removeAsset(named name: String) {
        let url = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }
}
