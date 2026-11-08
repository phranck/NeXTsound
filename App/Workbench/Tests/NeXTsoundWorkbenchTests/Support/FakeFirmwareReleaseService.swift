import Foundation
@testable import NeXTsoundWorkbench

/// A release service whose metadata and download URL are chosen by the test.
final class FakeFirmwareReleaseService: FirmwareReleaseService, @unchecked Sendable {
    var release: FirmwareRelease?
    var downloadURL = URL(fileURLWithPath: "/tmp/update.uf2")
    var error: (any Error)?

    init(release: FirmwareRelease? = nil) {
        self.release = release
    }

    func latestRelease() async throws -> FirmwareRelease {
        if let error {
            throw error
        }
        guard let release else {
            throw FirmwareReleaseError.noRelease
        }
        return release
    }

    func download(_: FirmwareRelease) async throws -> URL {
        if let error {
            throw error
        }
        return downloadURL
    }
}
