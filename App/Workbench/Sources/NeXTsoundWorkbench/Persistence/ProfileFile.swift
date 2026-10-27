import Foundation
import NeXTsoundCore
import SwiftUI
import UniformTypeIdentifiers

/// The canonical shared profile is the document's only stored state.
public struct ProfileFile: FileDocument, Equatable {
    public static let typeIdentifier = "work.layered.NeXTsound.profile"
    /// The extension of a profile file, which `App/project.yml` declares for the profile type.
    public static let fileExtension = "nxsbprofile"
    public static let readableContentTypes: [UTType] = [.neXTsoundProfile, .json]
    public static let writableContentTypes: [UTType] = [.neXTsoundProfile, .json]

    public private(set) var profile: SoundProfile

    public init(profile: SoundProfile = FactoryPreset.flat.makeProfile()) {
        self.profile = profile
    }

    public init(configuration: ReadConfiguration) throws {
        try self.init(file: configuration.file)
    }

    public init(file: FileWrapper) throws {
        guard
            file.isRegularFile,
            let data = file.regularFileContents
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        profile = try SoundProfile.decode(data)
    }
}

public extension ProfileFile {
    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        try encodedFile()
    }

    func encodedFile() throws -> FileWrapper {
        try FileWrapper(regularFileWithContents: profile.encoded())
    }

    /// Hides the extension of a written profile file, so the Finder shows the profile's name alone.
    ///
    /// SwiftUI's `fileExporter` offers no option for this, and the setting belongs to the file rather than to its type,
    /// so the exporter sets it on the file it wrote. The Finder still shows the extension while its "Show all filename
    /// extensions" setting is on.
    ///
    /// - Parameter url: The location of the written file.
    /// - Throws: The error of setting the file's resource value, such as a missing file.
    static func hideExtension(of url: URL) throws {
        var values = URLResourceValues()
        values.hasHiddenExtension = true
        var file = url
        try file.setResourceValues(values)
    }

    /// Commits one edit atomically. Incomplete names remain editable but cannot be saved.
    mutating func edit(_ mutation: (inout SoundProfile) throws -> Void) throws {
        var candidate = profile
        try mutation(&candidate)
        guard
            candidate.id == profile.id,
            candidate.revision == profile.revision
        else {
            throw WorkbenchError.documentIdentityChanged
        }
        try candidate.settings.validate()
        guard candidate != profile else {
            return
        }
        try candidate.advanceRevision()
        profile = candidate
    }
}
