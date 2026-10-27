import Foundation
import Testing
@testable import NeXTsoundWorkbench

struct ProcessPicotoolRunnerTests {
    /// A picotool that cannot be started reports why, instead of leaving the caller waiting for output that never ends.
    @Test func aPicotoolThatCannotStartFailsWithItsLaunchError() async throws {
        let probe = try SignedProbeBundle(picotool: Data("not executable".utf8), picotoolIsExecutable: false)
        defer { probe.remove() }
        let runner = try #require(ProcessPicotoolRunner(bundle: probe.bundle, appBundleURL: probe.url))

        let error = await #expect(throws: (any Error).self) {
            try await withTimeout(.seconds(10), throwing: BoardTransportError.timeout) {
                try await runner.run(arguments: [])
            }
        }
        #expect(error as? BoardTransportError != .timeout)
        #expect(error as? FlashError != .bundleSealBroken)
    }
}
