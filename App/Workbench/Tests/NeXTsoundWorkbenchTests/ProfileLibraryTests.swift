import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct ProfileLibraryTests {
    @Test func startsWithOneSelectedProfile() throws {
        let library = ProfileLibrary()
        try library.validate()
        #expect(library.profiles.count == 1)
        #expect(library.selectedProfile.id == library.selectedID)
    }

    @Test func roundTripPreservesContents() throws {
        let library = try makeLibrary()
        #expect(try ProfileLibrary.decode(library.encoded()) == library)
    }

    @Test func emptyOrDuplicateIdentitiesAreRejected() {
        #expect(throws: ProfileLibraryError.invalidLibrary) {
            try ProfileLibrary(profiles: [], selectedID: UUID())
        }
        let profile = SoundProfile(name: "A")
        #expect(throws: ProfileLibraryError.invalidLibrary) {
            try ProfileLibrary(profiles: [profile, profile], selectedID: profile.id)
        }
    }

    @Test func selectedIDMustReferenceAProfile() {
        let profile = SoundProfile(name: "A")
        #expect(throws: ProfileLibraryError.invalidLibrary) {
            try ProfileLibrary(profiles: [profile], selectedID: UUID())
        }
    }

    @Test func insertingAddsAndSelectsANewProfile() throws {
        var library = try makeLibrary()
        let previousRevision = library.revision
        let added = SoundProfile(name: "Added")
        try library.insert(added)
        #expect(library.profiles.count == 2)
        #expect(library.selectedID == added.id)
        #expect(library.revision == previousRevision + 1)
    }

    @Test func insertingTheSameIdentityAndContentsSelectsItWithoutDuplicating() throws {
        var library = try makeLibrary()
        let existing = library.selectedProfile
        try library.insert(SoundProfile(name: "Second"))
        try library.insert(existing)
        #expect(library.profiles.count == 2)
        #expect(library.selectedID == existing.id)
    }

    @Test func insertingADifferingProfileWithAnExistingIdentityIsRejected() throws {
        var library = try makeLibrary()
        var conflicting = library.selectedProfile
        conflicting.name = "Conflicting"
        #expect(throws: ProfileLibraryError.duplicateProfile) {
            try library.insert(conflicting)
        }
    }

    @Test func theProfileLimitIsEnforced() throws {
        var library = try makeLibrary()
        for index in 1 ..< ProfileLibrary.maximumProfiles {
            try library.insert(SoundProfile(name: "Profile \(index)"))
        }
        #expect(throws: ProfileLibraryError.profileLimit) {
            try library.insert(SoundProfile(name: "One too many"))
        }
    }

    @Test func removingTheLastProfileIsRejected() throws {
        var library = try makeLibrary()
        #expect(throws: ProfileLibraryError.lastProfile) {
            try library.removeSelected()
        }
    }

    @Test func removingSelectsARemainingProfile() throws {
        var library = try makeLibrary()
        try library.insert(SoundProfile(name: "Second"))
        let removedID = library.selectedID
        try library.removeSelected()
        #expect(library.profiles.allSatisfy { $0.id != removedID })
        #expect(library.selectedID != removedID)
    }

    @Test func updatingSelectedAdvancesRevisionAndKeepsIdentity() throws {
        var library = try makeLibrary()
        let previous = library.selectedProfile
        var proposed = previous
        proposed.settings.bands[0].gainDb = 2
        try library.updateSelected(proposed)
        #expect(library.selectedProfile.id == previous.id)
        #expect(library.selectedProfile.revision == previous.revision + 1)
    }

    @Test func restoringContentsRevertsAPriorMutationAndAdvancesRevision() throws {
        var library = try makeLibrary()
        let snapshot = library
        try library.insert(SoundProfile(name: "Second"))
        let revisionAfterInsert = library.revision
        try library.restoreContents(from: snapshot)
        #expect(library.profiles == snapshot.profiles)
        #expect(library.selectedID == snapshot.selectedID)
        #expect(library.revision == revisionAfterInsert + 1)
    }

    @Test func restoringIdenticalContentsIsANoOp() throws {
        var library = try makeLibrary()
        let snapshot = library
        try library.restoreContents(from: snapshot)
        #expect(library == snapshot)
    }

    @Test func oversizedFilesAreRejectedOnDecode() {
        let oversized = Data(count: ProfileLibrary.maximumFileBytes + 1)
        #expect(throws: ProfileLibraryError.oversizedFile) {
            try ProfileLibrary.decode(oversized)
        }
    }
}

private extension ProfileLibraryTests {
    func makeLibrary() throws -> ProfileLibrary {
        let profile = SoundProfile(name: "Test profile")
        return try ProfileLibrary(profiles: [profile], selectedID: profile.id)
    }
}
