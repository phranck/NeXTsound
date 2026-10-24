import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct FrontPanelMessageTests {
    @Test func eachMessageGivesWayToTheOnesBeforeIt() {
        var sources = FrontPanelMessageSources(board: .verified(fixtureCapabilities()))
        #expect(sources.message == FrontPanelMessage(text: "Edits play live", tone: .normal))
        sources.storageStatus = "Saving profiles…"
        #expect(sources.message == FrontPanelMessage(text: "Saving profiles…", tone: .normal))
        sources.validationProblem = "The profile is invalid."
        #expect(sources.message == FrontPanelMessage(text: "The profile is invalid.", isError: true))
        sources.error = "The board did not reply in time."
        #expect(sources.message == FrontPanelMessage(text: "The board did not reply in time.", isError: true))
        sources.saveSucceeded = true
        #expect(sources.message == FrontPanelMessage(text: "Settings saved"))
        sources.saveInProgress = "Saving to the SoundBox…"
        #expect(sources.message == FrontPanelMessage(text: "Saving to the SoundBox…"))
    }

    @Test func aMismatchShowsItsReasonAsAnError() {
        let sources = FrontPanelMessageSources(board: .mismatched("The reported serial does not match the enumerated device."))
        #expect(sources.message == FrontPanelMessage(text: "The reported serial does not match the enumerated device.", isError: true))
    }

    @Test func aFailedStorageReadsAsAnError() {
        let sources = FrontPanelMessageSources(storageStatus: "Changes are not saved.", storageFailed: true)
        #expect(sources.message == FrontPanelMessage(text: "Changes are not saved.", isError: true))
    }

    @Test func nothingIsSaidWithoutABoardOrNews() {
        #expect(FrontPanelMessageSources().message == nil)
    }
}

struct FrontPanelStatusTests {
    @Test func aVerifiedBoardShowsItsIdentityStorageAndLiveValues() {
        var capabilities = fixtureCapabilities()
        capabilities.deviceName = "Bedroom SoundBox"
        capabilities.flashSizeBytes = 4 * 1_048_576
        var runtime = DeviceRuntimeStatus()
        runtime.isStreaming = true
        runtime.hostVolumeDb = -12
        runtime.maxProcessingUs = 410
        runtime.blockDeadlineUs = 1000
        let status = FrontPanelStatus(board: .verified(capabilities), storage: .unsaved, runtime: runtime, message: nil)
        #expect(status.connection == "SoundBox connected")
        #expect(status.fields.map(\.value) == [
            "Bedroom SoundBox",
            "D4CDD489AFE28CC5",
            "1.0.0",
            "48 kHz 16/24 bit",
            "4 MB not saved",
            "playing -12.0 dB",
            "41% xrun 0/0",
        ])
    }

    @Test func aBoardThatIsNotVerifiedShowsNoValues() {
        #expect(FrontPanelStatus(board: .disconnected, storage: .unknown, runtime: nil, message: nil).fields.isEmpty)
        #expect(FrontPanelStatus(board: .mismatched("Reason"), storage: .unknown, runtime: nil, message: nil).fields.isEmpty)
    }

    /// Each owner field that is set gets a line after the live values, and the note shows its first line.
    @Test func ownerFieldsThatAreSetFollowTheLiveValues() {
        let day = CalendarDay(year: 2026, month: 10, day: 24)
        let metadata = OwnerMetadata(date: day, serialNumber: 1, owner: "Frank", note: "Built in Bregenz\nSecond line")
        let status = FrontPanelStatus(
            board: .verified(fixtureCapabilities()),
            storage: .saved,
            runtime: DeviceRuntimeStatus(),
            metadata: metadata,
            message: nil
        )
        #expect(status.fields.suffix(4).map(\.label) == ["Owner", "Unit", "Date", "Note"])
        let values = status.fields.suffix(4).map(\.value)
        #expect(values[0] == "Frank" && values[1] == "NXSB0001" && values[3] == "Built in Bregenz")
        #expect(["2026", "10", "24"].allSatisfy { values[2].contains($0) })
        let partial = FrontPanelStatus(
            board: .verified(fixtureCapabilities()),
            storage: .saved,
            runtime: nil,
            metadata: OwnerMetadata(serialNumber: 2),
            message: nil
        )
        #expect(partial.fields.map(\.label).suffix(2) == ["Flash", "Unit"])
    }

    /// Only an error's text brings a hidden status column back, so a message that reports progress or a hint leaves
    /// the column where it is.
    @Test func onlyAnErrorBringsTheStatusColumnBack() {
        func status(_ message: FrontPanelMessage?) -> FrontPanelStatus {
            FrontPanelStatus(connection: "SoundBox connected", fields: [], message: message)
        }
        #expect(status(FrontPanelMessage(text: "Save failed.", isError: true)).errorText == "Save failed.")
        #expect(status(FrontPanelMessage(text: "Edits play live", tone: .normal)).errorText == nil)
        #expect(status(nil).errorText == nil)
    }

    /// The column reads the model's board and news, so a board error reaches the message line, and a save that has
    /// just finished outranks it.
    @MainActor
    @Test func theColumnReadsTheModelsBoardAndNews() {
        let model = WorkbenchModel()
        model.errorMessage = "The board did not reply in time."
        let status = FrontPanelStatus(model: model, saveSucceeded: false)
        #expect(status.connection == "SoundBox not connected")
        #expect(status.message == FrontPanelMessage(text: "The board did not reply in time.", isError: true))
        #expect(FrontPanelStatus(model: model, saveSucceeded: true).message == FrontPanelMessage(text: "Settings saved"))
    }

    @Test func voiceOverReadsTheColumnOnlyWhileItStandsInTheDisplay() {
        let status = FrontPanelStatus(
            connection: "SoundBox connected",
            fields: [FrontPanelStatusField(label: "Name", value: "Bedroom")],
            message: FrontPanelMessage(text: "Edits play live", tone: .normal)
        )
        #expect(status.spokenDescription(profileName: "Warm", showsStatus: false) == "Warm")
        let spoken = status.spokenDescription(profileName: "Warm", showsStatus: true)
        #expect(spoken == "Warm. SoundBox connected. Name Bedroom. Edits play live")
    }
}
