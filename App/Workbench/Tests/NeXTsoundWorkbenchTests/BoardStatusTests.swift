import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct BoardStatusTests {
    @Test func aVerifiedBoardsLiveValuesAreReadAgainAndAgain() async throws {
        let statusCalls = CallCounter()
        var runtime = DeviceRuntimeStatus()
        runtime.isStreaming = true
        let monitor = try await verifiedMonitor(
            FakeBoardTransport(behavior: .success(fixtureCapabilities()), runtime: runtime, statusCalls: statusCalls),
            statusInterval: .milliseconds(10)
        )
        #expect(monitor.runtime?.isStreaming == true)
        let afterVerification = statusCalls.total
        await waitUntil { statusCalls.total >= afterVerification + 3 }
        #expect(statusCalls.total >= afterVerification + 3)
    }

    @Test func disconnectingStopsTheReadsAndForgetsTheLiveValues() async throws {
        let statusCalls = CallCounter()
        let discovery = FakeBoardDiscovery()
        let monitor = try await verifiedMonitor(
            FakeBoardTransport(behavior: .success(fixtureCapabilities()), statusCalls: statusCalls),
            discovery: discovery,
            statusInterval: .milliseconds(10)
        )
        discovery.simulateDisconnect()
        await waitUntil { monitor.state == .disconnected }
        #expect(monitor.runtime == nil)
        let afterDisconnect = statusCalls.total
        try await Task.sleep(for: .milliseconds(100))
        #expect(statusCalls.total == afterDisconnect)
    }

    @Test func noLiveValuesAreReadWhileAWriteIsOnTheWire() async throws {
        let statusCalls = CallCounter()
        let applyStateCalls = CallCounter()
        let monitor = try await verifiedMonitor(
            FakeBoardTransport(
                behavior: .success(fixtureCapabilities()),
                applyStateCalls: applyStateCalls,
                applyDelay: .milliseconds(300),
                statusCalls: statusCalls
            ),
            statusInterval: .milliseconds(10)
        )
        async let apply: Void = monitor.apply(DeviceSnapshot(profileID: UUID(), profileRevision: 1, settings: DSPSettings()))
        await waitUntil { applyStateCalls.total == 1 }
        // A read that began before the write may still arrive in the first moments; none may follow it.
        try await Task.sleep(for: .milliseconds(30))
        let duringWrite = statusCalls.total
        try await Task.sleep(for: .milliseconds(150))
        #expect(statusCalls.total == duringWrite)
        try await apply
    }
}
