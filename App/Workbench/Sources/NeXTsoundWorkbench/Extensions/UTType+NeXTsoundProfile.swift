import UniformTypeIdentifiers

public extension UTType {
    /// The content type of a profile file, a kind of JSON.
    static let neXTsoundProfile = UTType(exportedAs: ProfileFile.typeIdentifier, conformingTo: .json)
}
