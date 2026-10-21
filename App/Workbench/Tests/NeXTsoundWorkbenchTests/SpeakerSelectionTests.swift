import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct SpeakerSelectionTests {
    @Test func selectingASpeakerSnapshotsTheDriverRatherThanReferencingItLive() {
        let model = WorkbenchModel()
        var driver = DriverRecord(name: "Original driver")
        driver.nominalImpedanceOhms = 8

        model.selectSpeaker(driver)

        #expect(model.profile.speaker?.id == driver.id)
        #expect(model.profile.speaker?.name == "Original driver")
        #expect(model.profile.speaker?.nominalImpedanceOhms == 8)

        driver.name = "Renamed driver"
        #expect(model.profile.speaker?.name == "Original driver", "A later driver edit must not retroactively change the snapshot.")
    }

    @Test func selectingASpeakerWithFullThieleSmallDataSetsTheHighPassFromTheClosedBoxAlignment() {
        let model = WorkbenchModel()

        model.selectSpeaker(.tectonicTEBM28C10_4())

        #expect(model.profile.settings.highPassEnabled)
        #expect(abs(model.profile.settings.highPassHz - 176.394_613) < 0.001)
    }

    @Test func selectingASpeakerMissingVasLeavesTheHighPassUnchanged() {
        let model = WorkbenchModel()
        let before = model.profile.settings

        // tectonicTEBM28C10_4B has fsHz and qts but no vasLiters (datasheet does not state it).
        model.selectSpeaker(.tectonicTEBM28C10_4B())

        #expect(model.profile.settings.highPassEnabled == before.highPassEnabled)
        #expect(model.profile.settings.highPassHz == before.highPassHz)
    }

    @Test func selectingNilClearsTheSpeaker() {
        let model = WorkbenchModel()
        model.selectSpeaker(DriverRecord(name: "Some driver"))
        #expect(model.profile.speaker != nil)

        model.selectSpeaker(nil)

        #expect(model.profile.speaker == nil)
    }

    @Test func selectingASpeakerSupportsUndo() {
        let model = WorkbenchModel()
        let undoManager = UndoManager()
        let before = model.profile.speaker

        model.selectSpeaker(DriverRecord(name: "Some driver"), undoManager: undoManager)
        #expect(model.profile.speaker != nil)

        undoManager.undo()
        #expect(model.profile.speaker == before)
    }
}
