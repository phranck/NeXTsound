import Testing
@testable import NeXTsoundWorkbench

struct FlashPresentationTests {
    @Test func aRunningPhaseReadsAsATitle() {
        #expect(FlashPhase.writingAndVerifying.runningTitle == "Writing and verifying the firmware image…")
    }

    @Test func theRestartFollowsTheBoardsConnection() {
        #expect(FlashRestartStatus(connectionState: .verified(fixtureCapabilities())) == .reconnected(firmwareVersion: "1.0.0"))
        #expect(FlashRestartStatus(connectionState: .mismatched("Wrong firmware")) == .unverified)
        #expect(FlashRestartStatus(connectionState: .detected) == .waiting)
        #expect(FlashRestartStatus(connectionState: .disconnected) == .waiting)
    }
}
