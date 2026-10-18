import Foundation
import NeXTsoundCore
import SwiftUI
import UniformTypeIdentifiers

/// The canonical shared profile is the document's only stored state.
public struct ProfileFile: FileDocument, Equatable {
    public static let typeIdentifier = "work.layered.NeXTsound.profile"
    public static let fileExtension = "nxsprofile"
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

    mutating func apply(_ preset: FactoryPreset) throws {
        try edit { candidate in
            candidate.settings = preset.makeProfile().settings
            candidate.presetOrigin = preset.rawValue
        }
    }
}

public extension UTType {
    static let neXTsoundProfile = UTType(exportedAs: ProfileFile.typeIdentifier, conformingTo: .json)
}

public enum WorkbenchError: Error, Equatable, Sendable {
    case documentIdentityChanged
    case invalidSampleCount
    case invalidScale
}

extension WorkbenchError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .documentIdentityChanged: "An edit cannot replace the profile identity or revision."
        case .invalidSampleCount: "Choose between 2 and 2048 response samples."
        case .invalidScale: "The logarithmic control requires finite positive bounds."
        }
    }
}
