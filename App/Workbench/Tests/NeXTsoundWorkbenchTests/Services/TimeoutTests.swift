import Foundation
import Testing
@testable import NeXTsoundWorkbench

struct TimeoutTests {
    @Test func aBlockedOperationEndsAtTheTimeout() async {
        let start = ContinuousClock.now
        await #expect(throws: BoardTransportError.timeout) {
            try await withTimeout(.milliseconds(200), throwing: BoardTransportError.timeout) {
                try await blockOnQueue(for: .seconds(3))
            }
        }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func aFastOperationReturnsItsValue() async throws {
        let value = try await withTimeout(.seconds(2), throwing: BoardTransportError.timeout) { 42 }
        #expect(value == 42)
    }

    @Test func anOperationErrorReachesTheCaller() async {
        await #expect(throws: BoardTransportError.notConnected) {
            try await withTimeout(.seconds(2), throwing: BoardTransportError.timeout) { () async throws -> Int in
                throw BoardTransportError.notConnected
            }
        }
    }
}

private extension TimeoutTests {
    /// Blocks a dispatch queue the way a libusb control transfer does, ignoring cancellation.
    func blockOnQueue(for duration: Duration) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(label: "work.layered.NeXTsound.timeout-test").async {
                Thread.sleep(forTimeInterval: Double(duration.components.seconds))
                continuation.resume(returning: 1)
            }
        }
    }
}
