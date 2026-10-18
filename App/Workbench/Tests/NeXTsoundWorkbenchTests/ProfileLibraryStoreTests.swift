import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct ProfileLibraryStoreTests {
    @Test func loadingAMissingFileReturnsNil() async throws {
        let store = ProfileLibraryStore(fileURL: temporaryURL())
        #expect(try await store.load() == nil)
    }

    @Test func savedLibrariesRoundTripThroughLoad() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = ProfileLibraryStore(fileURL: url)
        _ = try await writer.load()
        let library = try makeLibrary()
        try await writer.save(library)

        let reader = ProfileLibraryStore(fileURL: url)
        #expect(try await reader.load() == library)
    }

    @Test func savingBeforeLoadingIsRejected() async throws {
        let store = ProfileLibraryStore(fileURL: temporaryURL())
        await #expect(throws: ProfileLibraryError.invalidLibrary) {
            try await store.save(makeLibrary())
        }
    }

    @Test func aCorruptFileFailsLoadAndStaysWriteDisabled() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a profile library".utf8).write(to: url)
        let store = ProfileLibraryStore(fileURL: url)
        await #expect(throws: (any Error).self) {
            try await store.load()
        }
        await #expect(throws: ProfileLibraryError.invalidLibrary) {
            try await store.save(makeLibrary())
        }
    }

    @Test func savingALowerOrEqualRevisionThanAlreadyStoredIsIgnoredNotOverwritten() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProfileLibraryStore(fileURL: url)
        _ = try await store.load()
        var library = try makeLibrary()
        try await store.save(library)
        try library.insert(SoundProfile(name: "Second"))
        try await store.save(library)

        let reader = ProfileLibraryStore(fileURL: url)
        let onDisk = try await reader.load()
        #expect(onDisk?.revision == library.revision)
    }

    @Test func importedProfilesAreDecodedFromTheirFile() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let profile = SoundProfile(name: "Imported")
        try profile.encoded().write(to: url)
        let imported = try ProfileLibraryStore.importedProfile(at: url)
        #expect(imported == profile)
    }

    @Test func oversizedImportFilesAreRejected() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(count: ProfileLibrary.maximumFileBytes + 1).write(to: url)
        #expect(throws: ProfileLibraryError.oversizedFile) {
            try ProfileLibraryStore.importedProfile(at: url)
        }
    }
}

private extension ProfileLibraryStoreTests {
    func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }

    func makeLibrary() throws -> ProfileLibrary {
        let profile = SoundProfile(name: "Test profile")
        return try ProfileLibrary(profiles: [profile], selectedID: profile.id)
    }
}
