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

    @Test func applyingToTheBoardSendsTheEditedMuteStateUnchanged() async throws {
        let (model, appliedSnapshots) = try await connectedModelWithFakeBoard()
        var profile = model.profile
        profile.settings.isMuted = true
        model.updateProfile(profile)

        await model.applyToBoard()

        #expect(model.errorMessage == nil)
        let sent = try #require(appliedSnapshots.snapshots.last)
        #expect(sent.settings.isMuted == true)
    }

    @Test func applyingToTheBoardSendsTheEditedAttenuationUnchanged() async throws {
        let (model, appliedSnapshots) = try await connectedModelWithFakeBoard()
        var profile = model.profile
        profile.settings.isMuted = false
        profile.settings.attenuationDb = -6
        model.updateProfile(profile)

        await model.applyToBoard()

        let sent = try #require(appliedSnapshots.snapshots.last)
        #expect(sent.settings.attenuationDb == -6)
    }

    @Test func applyingToTheBoardWithoutAConnectionIsASilentNoOp() async {
        let model = WorkbenchModel()
        await model.applyToBoard()
        #expect(model.errorMessage == nil)
    }

    @Test func editingTheProfileAutomaticallyAppliesToAConnectedBoardAfterTheDebounce() async throws {
        let (model, appliedSnapshots) = try await connectedModelWithFakeBoard()
        var profile = model.profile
        profile.settings.attenuationDb = -6
        model.updateProfile(profile)

        #expect(appliedSnapshots.snapshots.isEmpty, "The push is debounced, not immediate.")
        try await Task.sleep(for: .milliseconds(400))
        let sent = try #require(appliedSnapshots.snapshots.last)
        #expect(sent.settings.attenuationDb == -6)
    }

    @Test func editingTheProfileWithoutAConnectionNeverCallsTheTransport() async throws {
        let model = WorkbenchModel()
        model.addProfile()
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.errorMessage == nil)
    }

    @Test func aFailedApplySurfacesAnError() async throws {
        let discovery = FakeBoardDiscovery()
        let boards = BoardMonitor(discovery: discovery)
        let model = WorkbenchModel(boards: boards)
        boards.start()
        let capabilities = fixtureCapabilities()
        discovery.simulateConnect(
            BoardIdentitySnapshot(vendorID: 1, productID: 2, enumeratedSerial: capabilities.serial),
            transport: FakeBoardTransport(behavior: .success(capabilities), applyError: .invalidReport)
        )
        try await waitUntilVerified(boards)

        await model.applyToBoard()
        #expect(model.errorMessage != nil)
    }
}

@MainActor
private extension WorkbenchModelTests {
    func connectedModelWithFakeBoard() async throws -> (WorkbenchModel, SnapshotRecorder) {
        let discovery = FakeBoardDiscovery()
        let boards = BoardMonitor(discovery: discovery)
        let model = WorkbenchModel(boards: boards)
        boards.start()
        let capabilities = fixtureCapabilities()
        let appliedSnapshots = SnapshotRecorder()
        discovery.simulateConnect(
            BoardIdentitySnapshot(vendorID: 1, productID: 2, enumeratedSerial: capabilities.serial),
            transport: FakeBoardTransport(behavior: .success(capabilities), appliedSnapshots: appliedSnapshots)
        )
        try await waitUntilVerified(boards)
        return (model, appliedSnapshots)
    }

    func waitUntilVerified(_ monitor: BoardMonitor, timeout: Duration = .seconds(1)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if case .verified = monitor.state {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw FakeStorageError.simulatedFailure
    }
}
