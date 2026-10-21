import Foundation

/// The root directory the driver library and its asset files live under: the app's iCloud
/// ubiquity container when available (so the library and any user-added images/3D models sync
/// across the owner's Macs), falling back to the local Application Support directory when
/// iCloud is unavailable (not signed in, container not yet provisioned, or offline).
enum DriverStorageLocation {
    static func resolveRootDirectory() -> URL {
        let ubiquityDocuments = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
        if let ubiquityDocuments {
            return ubiquityDocuments
        }
        let fallback = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? FileManager.default.temporaryDirectory
        return fallback.appendingPathComponent("NeXTsound", isDirectory: true)
    }
}
