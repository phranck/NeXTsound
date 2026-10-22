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

struct DotMatrixWrapTests {
    @Test func aMessageWrapsBetweenWordsWithAHangingIndent() {
        let lines = DotMatrixWrap.lines(
            of: "The reported serial does not match the enumerated device.",
            width: 27,
            firstPrefix: "! ",
            laterPrefix: "  "
        )
        #expect(lines == ["! The reported serial does", "  not match the enumerated", "  device."])
    }

    @Test func aWordLongerThanALineTakesALineOfItsOwn() {
        let lines = DotMatrixWrap.lines(of: "a 0123456789abcdef", width: 10, firstPrefix: "> ", laterPrefix: "  ")
        #expect(lines == ["> a", "  0123456789abcdef"])
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
}
