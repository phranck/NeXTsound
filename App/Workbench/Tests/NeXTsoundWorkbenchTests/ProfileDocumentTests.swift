import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct ProfileDocumentTests {
    @Test func newDocumentsStartMutedWithUnknownContext() throws {
        let document = ProfileDocument()
        try document.profile.validate()
        #expect(document.profile.settings.isMuted)
        #expect(document.profile.speaker == nil)
        #expect(document.profile.enclosure == nil)
    }

    @Test func documentRoundTripPreservesCanonicalData() throws {
        let original = ProfileDocument(profile: fixture())
        let file = try original.encodedFile()
        #expect(try ProfileDocument(file: file) == original)
        #expect(try SoundProfile.decode(#require(file.regularFileContents)) == original.profile)
    }

    @Test func directoriesAndMalformedFilesAreRejected() {
        #expect(throws: (any Error).self) {
            try ProfileDocument(file: FileWrapper(directoryWithFileWrappers: [:]))
        }
        #expect(throws: (any Error).self) {
            try ProfileDocument(file: FileWrapper(regularFileWithContents: Data("invalid".utf8)))
        }
    }

    @Test func unsupportedFormatsAreRejected() throws {
        let data = try fixture().encoded()
        var fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        fields["formatVersion"] = 99
        let file = try FileWrapper(regularFileWithContents: JSONSerialization.data(withJSONObject: fields))
        #expect(throws: ProfileValidationError.unsupportedFormat(99)) {
            try ProfileDocument(file: file)
        }
    }

    @Test func editsAdvanceRevisionWithoutReplacingIdentity() throws {
        var document = ProfileDocument(profile: fixture())
        let previous = document.profile
        try document.edit { $0.settings.bands[1].gainDb = 3 }
        #expect(document.profile.revision == previous.revision + 1)
        #expect(document.profile.id == previous.id)
        #expect(document.profile.speaker == previous.speaker)
        #expect(document.profile.enclosure == previous.enclosure)
    }

    @Test func unchangedEditsDoNotAdvanceRevision() throws {
        var document = ProfileDocument(profile: fixture())
        let previous = document
        try document.edit { _ in }
        #expect(document == previous)
    }

    @Test func revisionExhaustionLeavesTheDocumentUnchanged() {
        var profile = fixture()
        profile.revision = .max
        var document = ProfileDocument(profile: profile)
        #expect(throws: ProfileValidationError.invalidRevision) {
            try document.edit { $0.name = "Changed" }
        }
        #expect(document.profile == profile)
    }

    @Test func failedMutationsLeaveTheDocumentUnchanged() {
        var document = ProfileDocument(profile: fixture())
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
        var document = ProfileDocument(profile: fixture())
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
        var document = ProfileDocument(profile: fixture())
        let previous = document
        #expect(throws: (any Error).self) {
            try document.edit { $0.settings.bands[0].gainDb = .nan }
        }
        #expect(document == previous)
    }

    @Test func incompleteNamesCanBeEditedButNotSaved() throws {
        var document = ProfileDocument(profile: fixture())
        try document.edit { $0.name = "" }
        #expect(document.profile.name.isEmpty)
        #expect(throws: ProfileValidationError.invalidName) {
            try document.encodedFile()
        }
    }

    @Test func presetsPreserveTheDocumentAndItsContext() throws {
        var document = ProfileDocument(profile: fixture())
        let previous = document.profile
        try document.apply(.warm)
        #expect(document.profile.id == previous.id)
        #expect(document.profile.name == previous.name)
        #expect(document.profile.speaker == previous.speaker)
        #expect(document.profile.enclosure == previous.enclosure)
        #expect(document.profile.settings == FactoryPreset.warm.makeProfile().settings)
        #expect(document.profile.settings.isMuted)
        #expect(document.profile.presetOrigin == FactoryPreset.warm.rawValue)
        #expect(document.profile.revision == previous.revision + 1)
    }
}

private extension ProfileDocumentTests {
    func fixture() -> SoundProfile {
        var profile = SoundProfile(name: "Test profile")
        profile.speaker = SpeakerRecord(name: "Synthetic test speaker")
        var enclosure = EnclosureRecord(name: "Synthetic test enclosure")
        enclosure.volume = EnclosureVolume(internalLiters: 0.5, displacementLiters: 0.01)
        profile.enclosure = enclosure
        return profile
    }
}
