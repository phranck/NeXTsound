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

    @Test func capturingASlotStoresTheCurrentDSPSettingsWithoutChangingTheLibrary() {
        let model = WorkbenchModel()
        var profile = model.profile
        profile.settings.attenuationDb = -12
        model.updateProfile(profile)
        let beforeCapture = model.library

        model.captureSlotA()

        #expect(model.slotA == model.profile.settings)
        #expect(model.library == beforeCapture, "Capture must not advance the revision or otherwise touch the library.")
    }

    @Test func capturingASlotIsIsolatedFromLaterEdits() {
        let model = WorkbenchModel()
        model.captureSlotA()
        let captured = model.slotA
        var edited = model.profile
        edited.settings.attenuationDb = -40
        model.updateProfile(edited)

        #expect(model.slotA == captured, "A later edit must not retroactively change what was captured.")
        #expect(model.profile.settings != captured)
    }

    @Test func recallingASlotChangesOnlyTheDSPSettings() throws {
        let model = WorkbenchModel()
        model.captureSlotA()
        let capturedSettings = try #require(model.slotA)
        var edited = model.profile
        edited.name = "Renamed"
        edited.settings.attenuationDb = -40
        model.updateProfile(edited)
        let beforeRecall = model.profile

        model.recallSlotA()

        #expect(model.profile.settings == capturedSettings)
        #expect(model.profile.name == beforeRecall.name, "Recall must not touch anything but DSP settings.")
        #expect(model.profile.id == beforeRecall.id)
    }

    @Test func recallingAnEmptySlotIsANoOp() {
        let model = WorkbenchModel()
        let before = model.library
        model.recallSlotA()
        model.recallSlotB()
        #expect(model.library == before)
    }

    @Test func recallingASlotSupportsUndo() {
        let model = WorkbenchModel()
        let undoManager = UndoManager()
        model.captureSlotB()
        var edited = model.profile
        edited.settings.attenuationDb = -40
        model.updateProfile(edited)
        let beforeRecall = model.profile

        model.recallSlotB(undoManager: undoManager)
        #expect(model.profile.settings == model.slotB)

        undoManager.undo()
        #expect(model.profile.settings == beforeRecall.settings)
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

    @Test func cancellingAnInFlightApplyNeverSurfacesAnError() async throws {
        let model = try await WorkbenchModel(boards: verifiedMonitor(FakeBoardTransport(
            behavior: .success(fixtureCapabilities()),
            applyDelay: .seconds(5)
        )))

        let inFlight = Task { await model.applyToBoard() }
        try await Task.sleep(for: .milliseconds(20))
        inFlight.cancel()
        _ = await inFlight.value

        #expect(model.errorMessage == nil, "A superseded apply is expected, not a failure.")
    }

    @Test func rapidEditsWhileAnApplyIsInFlightCollapseIntoOneFollowUpCall() async throws {
        let calls = CallCounter()
        let model = try await WorkbenchModel(boards: verifiedMonitor(FakeBoardTransport(
            behavior: .success(fixtureCapabilities()),
            applyStateCalls: calls,
            applyDelay: .milliseconds(200)
        )))

        async let first: Void = model.applyToBoard()
        try await Task.sleep(for: .milliseconds(10))
        async let second: Void = model.applyToBoard()
        try await Task.sleep(for: .milliseconds(10))
        async let third: Void = model.applyToBoard()
        _ = await (first, second, third)

        #expect(calls.total == 2, "Three overlapping edits must collapse into the in-flight call plus one coalesced follow-up.")
    }

    @Test func aFailedApplySurfacesAnError() async throws {
        let model = try await WorkbenchModel(boards: verifiedMonitor(FakeBoardTransport(
            behavior: .success(fixtureCapabilities()),
            applyError: .invalidReport
        )))

        await model.applyToBoard()
        #expect(model.errorMessage != nil)
    }
}

@MainActor
private extension WorkbenchModelTests {
    func connectedModelWithFakeBoard() async throws -> (WorkbenchModel, SnapshotRecorder) {
        let appliedSnapshots = SnapshotRecorder()
        let model = try await WorkbenchModel(boards: verifiedMonitor(FakeBoardTransport(
            behavior: .success(fixtureCapabilities()),
            appliedSnapshots: appliedSnapshots
        )))
        return (model, appliedSnapshots)
    }
}
