import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct FirmwareUpdateAnnouncementTests {
    @Test func aNewerReleaseIsAnnouncedOnceAfterLaunchAndVerification() async throws {
        let release = try makeRelease()
        let service = FakeFirmwareReleaseService(release: release)
        let discovery = FakeBoardDiscovery()
        let model = WorkbenchModel(
            storage: FakeProfileLibraryStorage(),
            boards: BoardMonitor(discovery: discovery),
            firmwareReleaseService: service
        )
        await model.start()
        #expect(service.latestReleaseCallCount == 0)

        connect(discovery)
        await waitUntil { model.availableFirmwareUpdate == release }
        #expect(model.availableFirmwareUpdate == release)
        #expect(FrontPanelStatus(model: model, saveSucceeded: false).message == FrontPanelMessage(
            text: "Firmware 99.0.0 is available. Open FLASH to update.",
            isLasting: true,
            isDismissible: true
        ))
        #expect(service.latestReleaseCallCount == 1)

        discovery.simulateDisconnect()
        await waitUntil { model.boards.state == .disconnected }
        connect(discovery)
        await waitUntil { model.boards.state == .verified(fixtureCapabilities()) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(service.latestReleaseCallCount == 1)

        model.dismissFirmwareUpdate()
        #expect(model.availableFirmwareUpdate == nil)
        #expect(FrontPanelStatus(model: model, saveSucceeded: false).message == FrontPanelMessage(text: "Edits play live", tone: .normal))
        #expect(service.latestReleaseCallCount == 1)
    }

    @Test func aCurrentReleaseDoesNotProduceAnUpdateMessage() async throws {
        let service = try FakeFirmwareReleaseService(release: FirmwareRelease(
            version: FirmwareVersion(major: 1, minor: 0, patch: 0),
            assetURL: makeAssetURL()
        ))
        let discovery = FakeBoardDiscovery()
        let model = WorkbenchModel(
            storage: FakeProfileLibraryStorage(),
            boards: BoardMonitor(discovery: discovery),
            firmwareReleaseService: service
        )
        await model.start()
        connect(discovery)
        await waitUntil { service.latestReleaseCallCount == 1 }

        #expect(model.availableFirmwareUpdate == nil)
        #expect(FrontPanelStatus(model: model, saveSucceeded: false).message == FrontPanelMessage(text: "Edits play live", tone: .normal))
    }

    @Test func aFailedBackgroundCheckStaysSilent() async {
        let service = FakeFirmwareReleaseService()
        let discovery = FakeBoardDiscovery()
        let model = WorkbenchModel(
            storage: FakeProfileLibraryStorage(),
            boards: BoardMonitor(discovery: discovery),
            firmwareReleaseService: service
        )
        await model.start()
        connect(discovery)
        await waitUntil { service.latestReleaseCallCount == 1 }

        #expect(model.availableFirmwareUpdate == nil)
        #expect(model.errorMessage == nil)
        #expect(FrontPanelStatus(model: model, saveSucceeded: false).message == FrontPanelMessage(text: "Edits play live", tone: .normal))
    }

    private func makeRelease() throws -> FirmwareRelease {
        try FirmwareRelease(version: FirmwareVersion(major: 99, minor: 0, patch: 0), assetURL: makeAssetURL())
    }

    private func makeAssetURL() throws -> URL {
        try #require(URL(string: "https://git.layered.work/phranck/NeXTsound/releases/download/firmware-v99.0.0/nxs_firmware.uf2"))
    }

    private func connect(_ discovery: FakeBoardDiscovery) {
        discovery.simulateConnect(
            BoardIdentitySnapshot(vendorID: 1, productID: 2, enumeratedSerial: fixtureCapabilities().serial),
            transport: FakeBoardTransport(behavior: .success(fixtureCapabilities()))
        )
    }
}
