import Foundation
import NeXTsoundCore
import OCCTSwift

public enum DriverAssetStoreError: Error, Equatable, Sendable {
    case missingFileExtension
    case copyFailed
    case invalidURL
    case downloadFailed
    case conversionFailed
}

extension DriverAssetStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingFileExtension: String(localized: "The chosen file has no file extension.")
        case .copyFailed: String(localized: "The file could not be imported.")
        case .invalidURL: String(localized: "That's not a valid URL.")
        case .downloadFailed: String(localized: "The file could not be downloaded.")
        case .conversionFailed: String(localized: "The STEP file could not be converted.")
        }
    }
}

/// STEP (`.step`/`.stp`) file extensions, matched case-insensitively against a candidate asset.
private let stepFileExtensions: Set<String> = ["step", "stp"]

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
    ///
    /// No Apple framework parses STEP (ISO 10303), so a `.step`/`.stp` source is first converted
    /// to STL via OCCTSwift (Open CASCADE); the preview path (Model I/O/SceneKit) stays unchanged.
    func importFile(at sourceURL: URL, forDriver driverID: UUID, role: String) throws -> String {
        var sourceURL = sourceURL
        var convertedTempURL: URL?
        if stepFileExtensions.contains(sourceURL.pathExtension.lowercased()) {
            let stlURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("stl")
            do {
                let shape = try Shape.load(from: sourceURL)
                try Exporter.writeSTL(shape: shape, to: stlURL)
            } catch {
                throw DriverAssetStoreError.conversionFailed
            }
            sourceURL = stlURL
            convertedTempURL = stlURL
        }
        defer {
            if let convertedTempURL {
                try? FileManager.default.removeItem(at: convertedTempURL)
            }
        }

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

    /// Downloads the file at `remoteURL` and imports it exactly like a locally picked file.
    func importRemoteFile(from remoteURL: URL, forDriver driverID: UUID, role: String) async throws -> String {
        guard remoteURL.scheme == "https" || remoteURL.scheme == "http" else {
            throw DriverAssetStoreError.invalidURL
        }
        let downloadedURL: URL
        let response: URLResponse
        do {
            (downloadedURL, response) = try await URLSession.shared.download(from: remoteURL)
        } catch {
            throw DriverAssetStoreError.downloadFailed
        }
        defer { try? FileManager.default.removeItem(at: downloadedURL) }
        let extensionName = resolvedFileExtension(for: remoteURL, response: response)
        guard !extensionName.isEmpty else {
            throw DriverAssetStoreError.missingFileExtension
        }
        let renamed = downloadedURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(extensionName)
        do {
            try FileManager.default.moveItem(at: downloadedURL, to: renamed)
        } catch {
            throw DriverAssetStoreError.downloadFailed
        }
        defer { try? FileManager.default.removeItem(at: renamed) }
        return try importFile(at: renamed, forDriver: driverID, role: role)
    }
}

private extension DriverAssetStore {
    func resolvedFileExtension(for remoteURL: URL, response: URLResponse) -> String {
        if !remoteURL.pathExtension.isEmpty {
            return remoteURL.pathExtension
        }
        if let suggested = response.suggestedFilename {
            let suggestedExtension = (suggested as NSString).pathExtension
            if !suggestedExtension.isEmpty {
                return suggestedExtension
            }
        }
        return ""
    }
}
