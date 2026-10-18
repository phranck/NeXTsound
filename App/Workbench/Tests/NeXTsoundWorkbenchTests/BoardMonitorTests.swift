import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct BoardMonitorTests {
    @Test func startsDisconnected() {
        let monitor = BoardMonitor(discovery: FakeBoardDiscovery())
        #expect(monitor.state == .disconnected)
    }

    @Test func aDisabledMonitorNeverStartsDiscovery() {
        let discovery = FakeBoardDiscovery()
        let monitor = BoardMonitor(isEnabled: false, discovery: discovery)
        monitor.start()
        #expect(discovery.startCount == 0)
        #expect(monitor.state == .disconnected)
    }

    @Test func connectingEntersDetectedBeforeTheReplyArrives() async {
        let discovery = FakeBoardDiscovery()
        let monitor = BoardMonitor(discovery: discovery)
        monitor.start()
        let capabilities = fixtureCapabilities()
        discovery.simulateConnect(
            BoardIdentitySnapshot(vendorID: 1, productID: 2, enumeratedSerial: capabilities.serial),
            transport: FakeBoardTransport(behavior: .delayed(capabilities, .milliseconds(100)))
        )
        let detected = await waitFor(monitor) { $0 == .detected }
        #expect(detected)
        let verified = await waitFor(monitor) {
            if case .verified = $0 {
                true
            } else {
                false
            }
        }
        #expect(verified)
    }

    @Test func connectingMovesToVerifiedOnMatchingSerial() async {
        let discovery = FakeBoardDiscovery()
        let monitor = BoardMonitor(discovery: discovery)
        monitor.start()
        let capabilities = fixtureCapabilities()
        discovery.simulateConnect(
            BoardIdentitySnapshot(vendorID: 1, productID: 2, enumeratedSerial: capabilities.serial),
            transport: FakeBoardTransport(behavior: .success(capabilities))
        )
        let verified = await waitFor(monitor) {
            if case .verified = $0 {
                true
            } else {
                false
            }
        }
        #expect(verified)
        #expect(monitor.state == .verified(capabilities))
    }

    @Test func aMismatchedEnumeratedSerialIsRejected() async {
        let discovery = FakeBoardDiscovery()
        let monitor = BoardMonitor(discovery: discovery)
        monitor.start()
        let capabilities = fixtureCapabilities(serial: "FROM-FIRMWARE")
        discovery.simulateConnect(
            BoardIdentitySnapshot(vendorID: 1, productID: 2, enumeratedSerial: "FROM-ENUMERATION"),
            transport: FakeBoardTransport(behavior: .success(capabilities))
        )
        let mismatched = await waitFor(monitor) {
            if case .mismatched = $0 {
                true
            } else {
                false
            }
        }
        #expect(mismatched)
    }

    @Test func aFailedCapabilityQueryIsReportedAsMismatched() async {
        let discovery = FakeBoardDiscovery()
        let monitor = BoardMonitor(discovery: discovery)
        monitor.start()
        discovery.simulateConnect(
            BoardIdentitySnapshot(vendorID: 1, productID: 2),
            transport: FakeBoardTransport(behavior: .failure(.invalidReport))
        )
        let mismatched = await waitFor(monitor) {
            if case .mismatched = $0 {
                true
            } else {
                false
            }
        }
        #expect(mismatched)
    }

    @Test func disconnectingReturnsToDisconnectedAndDiscardsAPendingReply() async {
        let discovery = FakeBoardDiscovery()
        let monitor = BoardMonitor(discovery: discovery)
        monitor.start()
        let capabilities = fixtureCapabilities()
        discovery.simulateConnect(
            BoardIdentitySnapshot(vendorID: 1, productID: 2, enumeratedSerial: capabilities.serial),
            transport: FakeBoardTransport(behavior: .delayed(capabilities, .milliseconds(100)))
        )
        discovery.simulateDisconnect()
        let disconnected = await waitFor(monitor) { $0 == .disconnected }
        #expect(disconnected)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(monitor.state == .disconnected)
    }

    @Test func reconnectingAfterADisconnectVerifiesAgain() async {
        let discovery = FakeBoardDiscovery()
        let monitor = BoardMonitor(discovery: discovery)
        monitor.start()
        let capabilities = fixtureCapabilities()
        discovery.simulateConnect(
            BoardIdentitySnapshot(vendorID: 1, productID: 2, enumeratedSerial: capabilities.serial),
            transport: FakeBoardTransport(behavior: .success(capabilities))
        )
        _ = await waitFor(monitor) {
            if case .verified = $0 {
                true
            } else {
                false
            }
        }
        discovery.simulateDisconnect()
        let disconnected = await waitFor(monitor) { $0 == .disconnected }
        #expect(disconnected)
        discovery.simulateConnect(
            BoardIdentitySnapshot(vendorID: 1, productID: 2, enumeratedSerial: capabilities.serial),
            transport: FakeBoardTransport(behavior: .success(capabilities))
        )
        let verified = await waitFor(monitor) {
            if case .verified = $0 {
                true
            } else {
                false
            }
        }
        #expect(verified)
    }
}

@MainActor
private extension BoardMonitorTests {
    func waitFor(_ monitor: BoardMonitor, timeout: Duration = .seconds(1), matches: (BoardConnectionState) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if matches(monitor.state) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return matches(monitor.state)
    }
}
