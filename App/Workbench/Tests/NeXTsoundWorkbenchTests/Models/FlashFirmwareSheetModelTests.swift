import Foundation
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

    @Test func aNewerReleaseIsOffered() async throws {
        let release = try FirmwareRelease(
            version: FirmwareVersion(major: 99, minor: 0, patch: 0),
            assetURL: #require(
                URL(string: "https://github.com/phranck/NeXTsound/releases/download/firmware-v99.0.0/nxs_firmware.uf2")
            )
        )
        let model = FlashFirmwareSheetModel(
            target: FlashTarget(applicationSerial: fixtureCapabilities().serial, applicationVersion: "1.0.0"),
            runner: FakePicotoolRunner(),
            releaseService: FakeFirmwareReleaseService(release: release)
        )
        await model.checkForUpdates()
        #expect(model.updateState == .available(release))
    }

    @Test func theCurrentReleaseIsUpToDate() async throws {
        let release = try FirmwareRelease(
            version: FirmwareVersion(major: 1, minor: 0, patch: 0),
            assetURL: #require(URL(string: "https://github.com/phranck/NeXTsound/releases/download/firmware-v1.0.0/nxs_firmware.uf2"))
        )
        let model = FlashFirmwareSheetModel(
            target: FlashTarget(applicationSerial: fixtureCapabilities().serial, applicationVersion: "1.0.0"),
            runner: FakePicotoolRunner(),
            releaseService: FakeFirmwareReleaseService(release: release)
        )
        await model.checkForUpdates()
        #expect(model.updateState == .upToDate)
    }

    @Test func anUpdateFailureDoesNotBlockTheSheet() async {
        let model = FlashFirmwareSheetModel(
            target: FlashTarget(applicationSerial: fixtureCapabilities().serial, applicationVersion: "1.0.0"),
            runner: FakePicotoolRunner(),
            releaseService: FakeFirmwareReleaseService()
        )
        await model.checkForUpdates()
        guard case let .failed(message) = model.updateState else {
            Issue.record("Expected the update check to fail")
            return
        }
        #expect(!message.isEmpty)
        #expect(model.canFlash)
    }

    @Test func installingAnUpdateDownloadsAndFlashesIt() async throws {
        let release = try FirmwareRelease(
            version: FirmwareVersion(major: 99, minor: 0, patch: 0),
            assetURL: #require(
                URL(string: "https://github.com/phranck/NeXTsound/releases/download/firmware-v99.0.0/nxs_firmware.uf2")
            )
        )
        let runner = FakePicotoolRunner()
        let model = FlashFirmwareSheetModel(
            target: FlashTarget(applicationSerial: fixtureCapabilities().serial, applicationVersion: "1.0.0"),
            runner: runner,
            releaseService: FakeFirmwareReleaseService(release: release)
        )
        await model.checkForUpdates()
        model.installUpdate()
        await waitUntil { model.outcome == .succeeded }
        #expect(runner.invocations.count == 2)
        #expect(runner.invocations[0].prefix(7) == ["load", "-v", "-F", "--vid", "0xcafe", "--pid", "0x4014"])
        #expect(runner.invocations[0].contains("/tmp/update.uf2"))
        #expect(runner.invocations[1] == ["reboot", "--ser", fixtureCapabilities().serial])
    }

    @Test func decliningAnUpdateDoesNotDownloadIt() async throws {
        let release = try FirmwareRelease(
            version: FirmwareVersion(major: 99, minor: 0, patch: 0),
            assetURL: #require(
                URL(string: "https://github.com/phranck/NeXTsound/releases/download/firmware-v99.0.0/nxs_firmware.uf2")
            )
        )
        let model = FlashFirmwareSheetModel(
            target: FlashTarget(applicationSerial: fixtureCapabilities().serial, applicationVersion: "1.0.0"),
            runner: FakePicotoolRunner(),
            releaseService: FakeFirmwareReleaseService(release: release)
        )
        await model.checkForUpdates()
        model.declineUpdate()
        #expect(model.updateState == .idle)
        #expect(model.outcome == .idle)
    }

    @Test func aBoardWithoutAVersionSkipsTheUpdateCheck() async {
        let model = FlashFirmwareSheetModel(
            target: FlashTarget(),
            runner: FakePicotoolRunner(),
            releaseService: FakeFirmwareReleaseService()
        )
        await model.checkForUpdates()
        #expect(model.updateState == .idle)
    }

    @Test func anUnreadableBoardVersionIsReported() async {
        let model = FlashFirmwareSheetModel(
            target: FlashTarget(applicationSerial: fixtureCapabilities().serial, applicationVersion: "not-a-version"),
            runner: FakePicotoolRunner(),
            releaseService: FakeFirmwareReleaseService()
        )
        await model.checkForUpdates()
        guard case .failed = model.updateState else {
            Issue.record("Expected an unsupported board version failure")
            return
        }
    }
}
