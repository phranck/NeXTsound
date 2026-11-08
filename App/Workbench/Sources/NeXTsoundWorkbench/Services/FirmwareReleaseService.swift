import Foundation

/// A firmware release that can be offered for installation.
public struct FirmwareRelease: Equatable, Sendable {
    public let version: FirmwareVersion
    public let assetURL: URL

    public init(version: FirmwareVersion, assetURL: URL) {
        self.version = version
        self.assetURL = assetURL
    }
}

/// Errors raised while reading or downloading a release.
enum FirmwareReleaseError: LocalizedError, Equatable {
    case noRelease
    case invalidResponse
    case invalidDestination
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .noRelease: String(localized: "No suitable firmware release was found.")
        case .invalidResponse: String(localized: "The firmware release response is invalid.")
        case .invalidDestination: String(localized: "The firmware download destination is not allowed.")
        case .responseTooLarge: String(localized: "The firmware response is too large.")
        }
    }
}

/// Reads release metadata and firmware images from Gitea.
public protocol FirmwareReleaseService: Sendable {
    func latestRelease() async throws -> FirmwareRelease
    func download(_ release: FirmwareRelease) async throws -> URL
}

/// The Gitea implementation of the release service.
public final class GiteaFirmwareReleaseService: NSObject, FirmwareReleaseService, URLSessionTaskDelegate, @unchecked Sendable {
    /// The repository and API root, fixed by the product rather than by release data.
    private static let repositoryURL = URL(string: "https://git.layered.work/api/v1/repos/phranck/NeXTsound")!
    /// The only host from which a release asset may be downloaded.
    private static let allowedHost = "git.layered.work"
    /// The path below which release assets live.
    private static let assetPathPrefix = "/phranck/NeXTsound/releases/download/"
    /// Maximum bytes accepted for a release list or a firmware image.
    private static let maximumResponseBytes = 4_000_000

    private var session: URLSession?
    private let fileManager: FileManager

    /// - Parameters:
    ///   - protocolClasses: URL protocol handlers used by tests; production uses none.
    ///   - fileManager: The file manager used for temporary downloads.
    public init(protocolClasses: [AnyClass]? = nil, fileManager: FileManager = .default) {
        let configuration = URLSessionConfiguration.ephemeral
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.fileManager = fileManager
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
}

public extension GiteaFirmwareReleaseService {
    func latestRelease() async throws -> FirmwareRelease {
        let data = try await data(from: Self.repositoryURL.appendingPathComponent("releases"))
        let releases = try JSONDecoder().decode([GiteaRelease].self, from: data)
        let candidates = releases.flatMap { release in
            release.assets.compactMap { asset -> FirmwareRelease? in
                guard
                    let version = FirmwareVersion(tag: release.tagName),
                    Self.isUsableAsset(asset, release: release)
                else {
                    return nil
                }
                return FirmwareRelease(version: version, assetURL: asset.browserDownloadURL)
            }
        }
        guard let latest = candidates.max(by: Self.isBefore) else {
            throw FirmwareReleaseError.noRelease
        }
        return latest
    }

    func download(_ release: FirmwareRelease) async throws -> URL {
        guard Self.isAllowedDownloadURL(release.assetURL) else {
            throw FirmwareReleaseError.invalidDestination
        }
        let data = try await data(from: release.assetURL)
        let destination = fileManager.temporaryDirectory.appendingPathComponent("nextsound-\(UUID().uuidString).uf2")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    /// Rejects every redirect instead of allowing a checked URL to lead to another host.
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct GiteaRelease: Decodable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GiteaAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case assets
    }
}

private struct GiteaAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private extension GiteaFirmwareReleaseService {
    /// Returns one response only when it is a successful, bounded HTTP response.
    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let session else {
            throw FirmwareReleaseError.invalidResponse
        }
        let (data, response) = try await session.data(for: request)
        guard
            let response = response as? HTTPURLResponse,
            response.statusCode == 200,
            data.count <= Self.maximumResponseBytes
        else {
            if data.count > Self.maximumResponseBytes {
                throw FirmwareReleaseError.responseTooLarge
            }
            throw FirmwareReleaseError.invalidResponse
        }
        return data
    }

    /// Whether a release asset has the expected name, size, scheme, host, and path.
    private static func isUsableAsset(_ asset: GiteaAsset, release: GiteaRelease) -> Bool {
        !release.draft && !release.prerelease && asset.name.hasSuffix(".uf2") && asset.name
            .count <= 255 && isAllowedDownloadURL(asset.browserDownloadURL)
    }

    /// Whether a URL points into this repository's release-asset area over HTTPS.
    private static func isAllowedDownloadURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == allowedHost && url.path.hasPrefix(assetPathPrefix) && url.absoluteString.count <= 2048
    }

    /// Orders two valid releases by their semantic versions.
    private static func isBefore(_ lhs: FirmwareRelease, _ rhs: FirmwareRelease) -> Bool {
        lhs.version < rhs.version
    }
}
