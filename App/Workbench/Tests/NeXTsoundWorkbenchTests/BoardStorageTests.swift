import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct BoardStorageTests {
    @Test func verifyingABoardReadsWhetherItPlaysItsSavedSettings() async throws {
        let monitor = try await verifiedMonitor(FakeBoardTransport(
            behavior: .success(fixtureCapabilities()),
            storage: FakeBoardStorage(.unsaved)
        ))
        #expect(monitor.storage == .unsaved)
    }

    @Test func disconnectingForgetsTheStorageState() async throws {
        let discovery = FakeBoardDiscovery()
        let monitor = try await verifiedMonitor(FakeBoardTransport(behavior: .success(fixtureCapabilities())), discovery: discovery)
        #expect(monitor.storage == .saved)
        discovery.simulateDisconnect()
        await waitUntil { monitor.state == .disconnected }
        #expect(monitor.storage == .unknown)
    }

    @Test func applyingMovesASavedBoardToUnsaved() async throws {
        let monitor = try await verifiedMonitor(FakeBoardTransport(behavior: .success(fixtureCapabilities())))
        try await monitor.apply(DeviceSnapshot(profileID: UUID(), profileRevision: 1, settings: DSPSettings()))
        #expect(monitor.storage == .unsaved)
    }

    @Test func persistingSavesTheBoardAndReadsItsStorageStateAgain() async throws {
        let writes = BoardWriteRecorder()
        let monitor = try await verifiedMonitor(FakeBoardTransport(
            behavior: .success(fixtureCapabilities()),
            writes: writes,
            storage: FakeBoardStorage(.unsaved)
        ))
        try await monitor.persist()
        #expect(writes.writes == [.persist])
        #expect(monitor.storage == .saved)
    }

    @Test func aFailedPersistLeavesTheBoardUnsaved() async throws {
        let monitor = try await verifiedMonitor(FakeBoardTransport(
            behavior: .success(fixtureCapabilities()),
            persistError: .timeout,
            storage: FakeBoardStorage(.unsaved)
        ))
        await #expect(throws: BoardTransportError.timeout) {
            try await monitor.persist()
        }
        #expect(monitor.storage == .unsaved)
    }

    @Test func persistingFailsWithoutAConnectedBoard() async {
        let monitor = BoardMonitor(discovery: FakeBoardDiscovery())
        await #expect(throws: BoardTransportError.notConnected) {
            try await monitor.persist()
        }
    }

    @Test func renamingReadsTheStorageStateAgain() async throws {
        let storage = FakeBoardStorage(.unsaved)
        let monitor = try await verifiedMonitor(FakeBoardTransport(behavior: .success(fixtureCapabilities()), storage: storage))
        // The firmware stores the settings it plays together with the new name.
        storage.state = .saved
        try await monitor.setDeviceName("Bedroom SoundBox")
        #expect(monitor.storage == .saved)
    }

    @Test func matchingGenerationsMeanTheBoardPlaysItsSavedSettings() {
        var status = DeviceRuntimeStatus()
        status.storageIsAvailable = true
        status.persistedGeneration = 7
        #expect(BoardStorageState(activeGeneration: 7, status: status) == .saved)
        #expect(BoardStorageState(activeGeneration: 8, status: status) == .unsaved)
        status.storageIsAvailable = false
        #expect(BoardStorageState(activeGeneration: 7, status: status) == .unavailable)
    }
}
