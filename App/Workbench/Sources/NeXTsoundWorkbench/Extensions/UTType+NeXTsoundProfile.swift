import UniformTypeIdentifiers

public extension UTType {
    /// The content type of a profile file. The file holds JSON, but the type is plain data, as `App/project.yml`
    /// declares it, because Quick Look renders a text preview of a JSON type that the Finder shows instead of its icon.
    static let neXTsoundProfile = UTType(exportedAs: ProfileFile.typeIdentifier, conformingTo: .data)
}
