import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct ProfileImportTests {
    @Test func importingAProfileInsertsItsDecodedContents() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let imported = SoundProfile(name: "Imported")
        try imported.encoded().write(to: url)

        let model = WorkbenchModel()
        await model.importProfile(at: url)
        #expect(model.library.profiles.contains(imported))
        #expect(model.library.selectedID == imported.id)
    }

    /// A file that launches the app arrives before the stored library has loaded. It lands in the loaded library,
    /// selected, whether it arrives before the front panel starts the load or while that load runs.
    @Test func aProfileFileOpenedAtLaunchLandsInTheLoadedLibrary() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".nxsbprofile")
        defer { try? FileManager.default.removeItem(at: url) }
        let opened = SoundProfile(name: "Opened")
        try opened.encoded().write(to: url)
        let stored = SoundProfile(name: "Stored")

        for startsFirst in [false, true] {
            let storage = try FakeProfileLibraryStorage(loadResult: .value(ProfileLibrary(profiles: [stored], selectedID: stored.id)))
            let (loadRelease, release) = AsyncStream<Void>.makeStream()
            storage.loadRelease = loadRelease
            let model = WorkbenchModel(storage: storage)
            let starting = startsFirst ? Task { await model.start() } : nil
            await Task.yield()
            let opening = Task { await model.openProfile(at: url) }
            await Task.yield()
            release.finish()
            await starting?.value
            await opening.value

            #expect(model.library.profiles.map(\.id) == [stored.id, opened.id])
            #expect(model.library.selectedID == opened.id)
        }
    }
}
