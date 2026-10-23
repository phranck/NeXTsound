import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct FlashFirmwareSheetModelTests {
    @Test func onlyABoardWithoutAKnownSerialIsHeldIntoBootselByHand() {
        #expect(FlashFirmwareSheetModel(target: FlashTarget(), runner: FakePicotoolRunner()).needsBootselByHand)
        let target = FlashTarget(applicationSerial: fixtureCapabilities().serial)
        #expect(!FlashFirmwareSheetModel(target: target, runner: FakePicotoolRunner()).needsBootselByHand)
    }

    /// Flash stays available until a flash succeeds, and only then does the sheet show the board's restart.
    @Test func aSuccessfulFlashEndsTheSheetsWork() async throws {
        let target = FlashTarget(applicationSerial: fixtureCapabilities().serial)
        let model = FlashFirmwareSheetModel(target: target, runner: FakePicotoolRunner())
        try #require(model.outcome == .idle, "The package's resources hold the firmware image.")
        #expect(model.canFlash)
        #expect(!model.showsRestartStatus)
        model.flash()
        await waitUntil { model.outcome == .succeeded }
        #expect(!model.canFlash)
        #expect(model.showsRestartStatus)
    }
}
