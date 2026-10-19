import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct WorkbenchModelTests {
    @Test func withoutStorageTheModelIsReadyImmediately() {
        let model = WorkbenchModel()
        #expect(model.isReady)
        #expect(model.storageStatus == "Temporary profile session")
    }

    @Test func startingLoadsTheStoredLibrary() async throws {
        let profile = SoundProfile(name: "Stored")
        let stored = try ProfileLibrary(profiles: [profile], selectedID: profile.id)
        let storage = FakeProfileLibraryStorage(loadResult: .value(stored))
        let model = WorkbenchModel(storage: storage)
        await model.start()
        #expect(model.isReady)
        #expect(model.library == stored)
        #expect(model.storageError == nil)
    }

    @Test func aFailedLoadStillBecomesReadyAndKeepsTheInMemoryLibrary() async {
        let storage = FakeProfileLibraryStorage(loadResult: .failure(FakeStorageError.simulatedFailure))
        let defaultLibrary = ProfileLibrary()
        let model = WorkbenchModel(library: defaultLibrary, storage: storage)
        await model.start()
        #expect(model.isReady, "A broken store must never trap the user out of the workbench.")
        #expect(model.storageError != nil)
        #expect(model.library == defaultLibrary)
        model.addProfile()
        #expect(model.library.profiles.count == 2, "Editing must keep working while persistence is broken.")
    }

    @Test func addingAProfileSelectsItAndSchedulesASave() async throws {
        let storage = FakeProfileLibraryStorage(loadResult: .value(nil))
        let model = WorkbenchModel(storage: storage)
        await model.start()
        model.addProfile()
        #expect(model.library.profiles.count == 2)
        #expect(model.library.selectedID == model.profile.id)
        try await Task.sleep(for: .milliseconds(400))
        #expect(storage.savedLibraries.last == model.library)
    }

    @Test func removingTheLastProfileLeavesTheLibraryUnchangedAndReportsAnError() {
        let model = WorkbenchModel()
        model.removeProfile()
        #expect(model.library.profiles.count == 1)
        #expect(model.errorMessage != nil)
    }

    @Test func undoRestoresThePreviousLibrary() {
        let model = WorkbenchModel()
        let undoManager = UndoManager()
        let before = model.library
        model.addProfile(undoManager: undoManager)
        #expect(model.library.profiles.count == 2)
        undoManager.undo()
        #expect(model.library.profiles == before.profiles)
        #expect(model.library.selectedID == before.selectedID)
    }

    @Test func redoReappliesTheUndoneChange() {
        let model = WorkbenchModel()
        let undoManager = UndoManager()
        model.addProfile(undoManager: undoManager)
        let afterAdd = model.library
        undoManager.undo()
        undoManager.redo()
        #expect(model.library.profiles == afterAdd.profiles)
    }

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

    @Test func flushSavesImmediatelyWithoutWaitingForTheDebounce() async throws {
        let storage = FakeProfileLibraryStorage(loadResult: .value(nil))
        let model = WorkbenchModel(storage: storage)
        await model.start()
        model.addProfile()
        try await model.flush()
        #expect(storage.savedLibraries.last == model.library)
    }

    @Test func aSaveFailureSurfacesAnErrorButEditingContinues() async throws {
        let storage = FakeProfileLibraryStorage(loadResult: .value(nil))
        storage.saveError = FakeStorageError.simulatedFailure
        let model = WorkbenchModel(storage: storage)
        await model.start()
        model.addProfile()
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.storageError != nil)
        model.addProfile()
        #expect(model.library.profiles.count == 3)
    }
}
