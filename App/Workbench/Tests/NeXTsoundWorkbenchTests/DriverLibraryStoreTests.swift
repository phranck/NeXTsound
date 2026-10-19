import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct DriverLibraryStoreTests {
    @Test func loadingAMissingFileReturnsNil() async throws {
        let store = DriverLibraryStore(fileURL: temporaryURL())
        #expect(try await store.load() == nil)
    }

    @Test func savedLibrariesRoundTripThroughLoad() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = DriverLibraryStore(fileURL: url)
        let library = DriverLibrary()
        try await writer.save(library)

        let reader = DriverLibraryStore(fileURL: url)
        #expect(try await reader.load() == library)
    }

    @Test func aCorruptFileFailsLoad() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a driver library".utf8).write(to: url)
        let store = DriverLibraryStore(fileURL: url)
        await #expect(throws: (any Error).self) {
            try await store.load()
        }
    }

    @Test func anOversizedFileIsRejected() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(count: DriverLibrary.maximumFileBytes + 1).write(to: url)
        let store = DriverLibraryStore(fileURL: url)
        await #expect(throws: DriverLibraryError.oversizedFile) {
            try await store.load()
        }
    }

    @Test func savingOverwritesThePreviousContents() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DriverLibraryStore(fileURL: url)
        try await store.save(DriverLibrary())
        var updated = DriverLibrary()
        try updated.insert(DriverRecord(name: "Second driver"))
        try await store.save(updated)

        let reader = DriverLibraryStore(fileURL: url)
        #expect(try await reader.load() == updated)
    }
}

private extension DriverLibraryStoreTests {
    func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }
}
