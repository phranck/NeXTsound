import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct BoardSaveTests {
    @Test func savingToTheBoardAppliesTheProfileBeforePersistingIt() async throws {
        let writes = BoardWriteRecorder()
        let model = try await WorkbenchModel(boards: verifiedMonitor(FakeBoardTransport(
            behavior: .success(fixtureCapabilities()),
            writes: writes,
            storage: FakeBoardStorage(.unsaved)
        )))
        #expect(model.boardStorageStatus == "Settings not saved on the SoundBox")

        await model.saveToBoard()

        #expect(writes.writes == [.apply(currentSnapshot(of: model)), .persist])
        #expect(model.errorMessage == nil)
        #expect(!model.isSavingToBoard)
        #expect(model.boardStorageStatus == "Settings saved on the SoundBox")
    }

    @Test func aFailedSaveSurfacesAnErrorAndLeavesTheBoardUnsaved() async throws {
        let model = try await WorkbenchModel(boards: verifiedMonitor(FakeBoardTransport(
            behavior: .success(fixtureCapabilities()),
            persistError: .timeout
        )))

        await model.saveToBoard()

        #expect(model.errorMessage != nil)
        #expect(!model.isSavingToBoard)
        #expect(model.boardStorageStatus == "Settings not saved on the SoundBox")
    }

    @Test func aBoardWithoutStorageCannotSave() async throws {
        let writes = BoardWriteRecorder()
        let model = try await WorkbenchModel(boards: verifiedMonitor(FakeBoardTransport(
            behavior: .success(fixtureCapabilities()),
            writes: writes,
            storage: FakeBoardStorage(.unavailable)
        )))
        #expect(!model.canSaveToBoard)

        await model.saveToBoard()

        #expect(writes.writes.isEmpty)
        #expect(model.boardStorageStatus == "This SoundBox cannot save settings")
    }

    @Test func savingWithoutAConnectionIsASilentNoOp() async {
        let model = WorkbenchModel()
        #expect(!model.canSaveToBoard)

        await model.saveToBoard()

        #expect(model.errorMessage == nil)
        #expect(!model.isSavingToBoard)
        #expect(model.boardStorageStatus == nil)
    }

    @Test func aSaveRequestedWhileAnApplyRunsFollowsIt() async throws {
        let writes = BoardWriteRecorder()
        let model = try await WorkbenchModel(boards: verifiedMonitor(FakeBoardTransport(
            behavior: .success(fixtureCapabilities()),
            applyDelay: .milliseconds(200),
            writes: writes
        )))

        async let apply: Void = model.applyToBoard()
        try await Task.sleep(for: .milliseconds(10))
        await model.saveToBoard()
        #expect(model.isSavingToBoard, "The save waits for the apply already on the wire.")
        await apply

        let snapshot = currentSnapshot(of: model)
        #expect(writes.writes == [.apply(snapshot), .apply(snapshot), .persist])
        #expect(!model.isSavingToBoard)
        #expect(model.boards.storage == .saved)
    }
}

@MainActor
private extension BoardSaveTests {
    func currentSnapshot(of model: WorkbenchModel) -> DeviceSnapshot {
        DeviceSnapshot(profileID: model.profile.id, profileRevision: model.profile.revision, settings: model.profile.settings)
    }
}
