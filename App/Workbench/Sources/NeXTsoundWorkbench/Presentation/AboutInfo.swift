import Foundation

/// What the About window shows of the app's bundle: its version with the build, and its copyright.
public struct AboutInfo: Equatable, Sendable {
    /// The version people read, the bundle's `CFBundleShortVersionString`.
    public let version: String
    /// The build, the bundle's `CFBundleVersion`.
    public let build: String
    /// The bundle's `NSHumanReadableCopyright`, or nil without one.
    public let copyright: String?

    public init(version: String, build: String, copyright: String?) {
        self.version = version
        self.build = build
        self.copyright = copyright
    }
}

public extension AboutInfo {
    /// The app bundle's own values, localized where the bundle localizes them.
    static var app: AboutInfo {
        AboutInfo { key in Bundle.main.object(forInfoDictionaryKey: key) }
    }

    /// The values of the Info.plist that `value` reads, which returns the object for a key. A missing version or
    /// build reads as an empty text.
    init(value: (String) -> Any?) {
        self.init(
            version: value("CFBundleShortVersionString") as? String ?? "",
            build: value("CFBundleVersion") as? String ?? "",
            copyright: value("NSHumanReadableCopyright") as? String
        )
    }
}

extension AboutInfo {
    /// The version with its build in parentheses, as the About window's readout shows it.
    var versionLine: String {
        String(
            localized: "Version \(version) (\(build))",
            comment: "The About window's version readout: the version, then the build in parentheses."
        )
    }
}
