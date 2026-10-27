import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct ProfileFileTests {
    @Test func newDocumentsStartMutedWithUnknownContext() throws {
        let document = ProfileFile()
        try document.profile.validate()
        #expect(document.profile.settings.isMuted)
        #expect(document.profile.speaker == nil)
        #expect(document.profile.enclosure == nil)
    }

    @Test func documentRoundTripPreservesCanonicalData() throws {
        let original = ProfileFile(profile: fixture())
        let file = try original.encodedFile()
        #expect(try ProfileFile(file: file) == original)
        #expect(try SoundProfile.decode(#require(file.regularFileContents)) == original.profile)
    }

    @Test func directoriesAndMalformedFilesAreRejected() {
        #expect(throws: (any Error).self) {
            try ProfileFile(file: FileWrapper(directoryWithFileWrappers: [:]))
        }
        #expect(throws: (any Error).self) {
            try ProfileFile(file: FileWrapper(regularFileWithContents: Data("invalid".utf8)))
        }
    }

    @Test func unsupportedFormatsAreRejected() throws {
        let data = try fixture().encoded()
        var fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        fields["formatVersion"] = 99
        let file = try FileWrapper(regularFileWithContents: JSONSerialization.data(withJSONObject: fields))
        #expect(throws: ProfileValidationError.unsupportedFormat(99)) {
            try ProfileFile(file: file)
        }
    }

    @Test func editsAdvanceRevisionWithoutReplacingIdentity() throws {
        var document = ProfileFile(profile: fixture())
        let previous = document.profile
        try document.edit { $0.settings.bands[1].gainDb = 3 }
        #expect(document.profile.revision == previous.revision + 1)
        #expect(document.profile.id == previous.id)
        #expect(document.profile.speaker == previous.speaker)
        #expect(document.profile.enclosure == previous.enclosure)
    }

    @Test func unchangedEditsDoNotAdvanceRevision() throws {
        var document = ProfileFile(profile: fixture())
        let previous = document
        try document.edit { _ in }
        #expect(document == previous)
    }

    @Test func revisionExhaustionLeavesTheDocumentUnchanged() {
        var profile = fixture()
        profile.revision = .max
        var document = ProfileFile(profile: profile)
        #expect(throws: ProfileValidationError.invalidRevision) {
            try document.edit { $0.name = "Changed" }
        }
        #expect(document.profile == profile)
    }

    @Test func failedMutationsLeaveTheDocumentUnchanged() {
        var document = ProfileFile(profile: fixture())
        let previous = document
        #expect(throws: CocoaError(.userCancelled)) {
            try document.edit { candidate in
                candidate.name = "Changed"
                throw CocoaError(.userCancelled)
            }
        }
        #expect(document == previous)
    }

    @Test func identityAndRevisionCannotBeReplacedByAnEdit() {
        var document = ProfileFile(profile: fixture())
        let previous = document
        #expect(throws: WorkbenchError.documentIdentityChanged) {
            try document.edit { $0.id = UUID() }
        }
        #expect(document == previous)
        #expect(throws: WorkbenchError.documentIdentityChanged) {
            try document.edit { $0.revision += 1 }
        }
        #expect(document == previous)
    }

    @Test func invalidSettingsLeaveTheDocumentUnchanged() {
        var document = ProfileFile(profile: fixture())
        let previous = document
        #expect(throws: (any Error).self) {
            try document.edit { $0.settings.bands[0].gainDb = .nan }
        }
        #expect(document == previous)
    }

    @Test func incompleteNamesCanBeEditedButNotSaved() throws {
        var document = ProfileFile(profile: fixture())
        try document.edit { $0.name = "" }
        #expect(document.profile.name.isEmpty)
        #expect(throws: ProfileValidationError.invalidName) {
            try document.encodedFile()
        }
    }

    @Test func anExportedFileHidesItsExtension() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var url = directory.appendingPathComponent("Profile").appendingPathExtension(ProfileFile.fileExtension)
        try ProfileFile(profile: fixture()).encodedFile().write(to: url, originalContentsURL: nil)

        try ProfileFile.hideExtension(of: url)

        url.removeAllCachedResourceValues()
        #expect(try url.resourceValues(forKeys: [.hasHiddenExtensionKey]).hasHiddenExtension == true)
    }
}

private extension ProfileFileTests {
    func fixture() -> SoundProfile {
        var profile = SoundProfile(name: "Test profile")
        profile.speaker = SpeakerRecord(name: "Synthetic test speaker")
        var enclosure = EnclosureRecord(name: "Synthetic test enclosure")
        enclosure.volume = EnclosureVolume(internalLiters: 0.5, displacementLiters: 0.01)
        profile.enclosure = enclosure
        return profile
    }
}
