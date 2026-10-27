import Foundation
import Testing
@testable import NeXTsoundWorkbench

struct ProcessPicotoolRunnerTests {
    /// A picotool that cannot be started reports why, instead of leaving the caller waiting for output that never ends.
    @Test func aPicotoolThatCannotStartFailsWithItsLaunchError() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nxs-launch-\(UUID().uuidString)", isDirectory: true)
        let resources = directory.appendingPathComponent("Probe.bundle/Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not executable".utf8).write(to: resources.appendingPathComponent("picotool"))
        let bundle = try #require(Bundle(url: directory.appendingPathComponent("Probe.bundle")))
        let runner = try #require(ProcessPicotoolRunner(bundle: bundle))

        let error = await #expect(throws: (any Error).self) {
            try await withTimeout(.seconds(10), throwing: BoardTransportError.timeout) {
                try await runner.run(arguments: [])
            }
        }
        #expect(error as? BoardTransportError != .timeout)
    }
}
