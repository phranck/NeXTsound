import Foundation
import Testing
@testable import NeXTsoundWorkbench

@MainActor
@Suite(.serialized)
struct FirmwareReleaseServiceTests {
    @Test func selectsTheNewestPublicReleaseWithAFirmwareAsset() async throws {
        let releaseURL = try makeReleaseURL()
        let data = Data(#"""
        [
          {
            "tag_name": "firmware-v0.4.0",
            "draft": false,
            "prerelease": false,
            "assets": [
              {
                "name": "NeXTsound-0.4.0.zip",
                "browser_download_url": "https://github.com/phranck/NeXTsound/releases/download/firmware-v0.4.0/NeXTsound-0.4.0.zip"
              }
            ]
          },
          {
            "tag_name": "firmware-v0.6.4",
            "draft": false,
            "prerelease": false,
            "assets": [
              {
                "name": "nxs_firmware.uf2",
                "browser_download_url": "https://github.com/phranck/NeXTsound/releases/download/firmware-v0.6.4/nxs_firmware.uf2"
              }
            ]
          },
          {
            "tag_name": "firmware-v99.0.0",
            "draft": true,
            "prerelease": false,
            "assets": [
              {
                "name": "nxs_firmware.uf2",
                "browser_download_url": "https://github.com/phranck/NeXTsound/releases/download/firmware-v99.0.0/nxs_firmware.uf2"
              }
            ]
          }
        ]
        """#.utf8)
        let service = makeService(
            statusCode: 200,
            data: data,
            expectedURL: URL(string: "https://api.github.com/repos/phranck/NeXTsound/releases")
        )
        let release = try await service.latestRelease()
        #expect(release.version == FirmwareVersion(major: 0, minor: 6, patch: 4))
        #expect(release.assetURL == releaseURL)
    }

    @Test func reportsWhenNoSuitableReleaseExists() async {
        let service = makeService(statusCode: 200, data: Data("[]".utf8))
        await #expect(throws: FirmwareReleaseError.noRelease) {
            _ = try await service.latestRelease()
        }
    }

    @Test func downloadsTheFirmwareToATemporaryFile() async throws {
        let releaseURL = try makeReleaseURL()
        let service = makeService(statusCode: 200, data: Data("firmware".utf8))
        let release = FirmwareRelease(version: FirmwareVersion(major: 0, minor: 6, patch: 4), assetURL: releaseURL)
        let fileURL = try await service.download(release)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(fileURL.pathExtension == "uf2")
    }

    @Test func rejectsADownloadFromAnotherHost() async throws {
        let service = makeService(statusCode: 200, data: Data())
        let release = try FirmwareRelease(
            version: FirmwareVersion(major: 0, minor: 6, patch: 4),
            assetURL: #require(URL(string: "https://example.com/nxs_firmware.uf2"))
        )
        await #expect(throws: FirmwareReleaseError.invalidDestination) {
            _ = try await service.download(release)
        }
    }

    @Test func rejectsARedirect() throws {
        let releaseURL = try makeReleaseURL()
        let service = GitHubFirmwareReleaseService()
        let response = try #require(HTTPURLResponse(url: releaseURL, statusCode: 301, httpVersion: nil, headerFields: nil))
        var completion: URLRequest?
        service.urlSession(
            .shared,
            task: URLSession.shared.dataTask(with: releaseURL),
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: releaseURL)
        ) { request in
            completion = request
        }
        #expect(completion == nil)
    }

    @Test func allowsARedirectToGitHubReleaseAssets() throws {
        let releaseURL = try makeReleaseURL()
        let service = GitHubFirmwareReleaseService()
        let response = try #require(HTTPURLResponse(url: releaseURL, statusCode: 302, httpVersion: nil, headerFields: nil))
        let redirectURL = try #require(URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/asset"))
        var completion: URLRequest?
        service.urlSession(
            .shared,
            task: URLSession.shared.dataTask(with: releaseURL),
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: redirectURL)
        ) { request in
            completion = request
        }
        #expect(completion?.url == redirectURL)
    }

    @Test func rejectsAnOversizedResponse() async throws {
        let releaseURL = try makeReleaseURL()
        let service = makeService(statusCode: 200, data: Data(repeating: 0, count: 4_000_001))
        let release = FirmwareRelease(version: FirmwareVersion(major: 0, minor: 6, patch: 4), assetURL: releaseURL)
        await #expect(throws: FirmwareReleaseError.responseTooLarge) {
            _ = try await service.download(release)
        }
    }

    /// The URL used by the release and download tests.
    private func makeReleaseURL() throws -> URL {
        try #require(URL(string: "https://github.com/phranck/NeXTsound/releases/download/"
                + "firmware-v0.6.4/nxs_firmware.uf2"))
    }

    /// Creates a client whose URLSession returns the chosen status and body.
    private func makeService(
        statusCode: Int,
        data: Data,
        location: String? = nil,
        expectedURL: URL? = nil
    ) -> GitHubFirmwareReleaseService {
        FakeURLProtocol.handler = { request in
            let url = try #require(request.url)
            if let expectedURL {
                #expect(url == expectedURL)
            }
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: location.map { ["Location": $0] }
            ))
            return (response, data)
        }
        return GitHubFirmwareReleaseService(protocolClasses: [FakeURLProtocol.self])
    }
}
