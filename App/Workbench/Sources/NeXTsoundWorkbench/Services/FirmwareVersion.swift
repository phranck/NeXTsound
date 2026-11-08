import Foundation

/// A semantic firmware version read from a Gitea tag or a board's capabilities.
public struct FirmwareVersion: Comparable, Sendable {
    /// The tag prefix used by Gitea firmware releases.
    private static let tagPrefix = "firmware-v"
    /// The number of numeric components in a semantic version.
    private static let componentCount = 3
    /// The suffix accepted for a local, uncommitted firmware build.
    private static let dirtySuffix = "dirty"

    public let major: UInt32
    public let minor: UInt32
    public let patch: UInt32

    public init(major: UInt32, minor: UInt32, patch: UInt32) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Reads a version from a `firmware-v` tag.
    init?(tag: String) {
        guard tag.hasPrefix(Self.tagPrefix) else {
            return nil
        }
        self.init(numericVersion: String(tag.dropFirst(Self.tagPrefix.count)))
    }

    /// Reads a version from capabilities, ignoring a `-dirty` suffix.
    init?(boardVersion: String) {
        let suffixParts = boardVersion.split(separator: "-", omittingEmptySubsequences: false)
        if suffixParts.count > 2 || (suffixParts.count == 2 && suffixParts[1] != Self.dirtySuffix) {
            return nil
        }
        guard let base = suffixParts.first else {
            return nil
        }
        self.init(numericVersion: String(base))
    }

    /// Reads exactly three bounded numeric components.
    private init?(numericVersion: String) {
        let parts = numericVersion.split(separator: ".", omittingEmptySubsequences: false)
        guard
            parts.count == Self.componentCount,
            parts.allSatisfy({ Self.isValidComponent(String($0)) })
        else {
            return nil
        }
        let values = parts.compactMap { UInt32(String($0)) }
        guard values.count == Self.componentCount else {
            return nil
        }
        self.init(major: values[0], minor: values[1], patch: values[2])
    }

    /// Whether one component contains only digits and has no leading zero.
    private static func isValidComponent(_ component: String) -> Bool {
        !component.isEmpty && component.allSatisfy(\.isNumber) && (component.count == 1 || !component.hasPrefix("0"))
    }

    /// The version in the form shown by an update prompt.
    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: FirmwareVersion, rhs: FirmwareVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}
