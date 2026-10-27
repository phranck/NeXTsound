import Foundation
import Testing
@testable import NeXTsoundWorkbench

struct BundleSealTests {
    @Test func anUnchangedSignedBundlePasses() async throws {
        let probe = try SignedProbeBundle()
        defer { probe.remove() }
        try await BundleSeal.verify(probe.url)
    }

    @Test func aChangedResourceBreaksTheSeal() async throws {
        let probe = try SignedProbeBundle()
        defer { probe.remove() }
        try probe.tamper()
        await #expect(throws: FlashError.bundleSealBroken) {
            try await BundleSeal.verify(probe.url)
        }
    }

    /// More checks at once than a CI machine's concurrency pool has threads, each awaited from a task of the pool.
    @Test func manyChecksAtOnceAllFinish() async throws {
        let probe = try SignedProbeBundle()
        defer { probe.remove() }
        try await withTimeout(.seconds(30), throwing: BoardTransportError.timeout) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 16 {
                    group.addTask { try await BundleSeal.verify(probe.url) }
                }
                try await group.waitForAll()
            }
        }
    }

    @Test func theRunnerRefusesPicotoolFromATamperedBundle() async throws {
        let probe = try SignedProbeBundle()
        defer { probe.remove() }
        let runner = try #require(ProcessPicotoolRunner(bundle: probe.bundle, appBundleURL: probe.url))
        #expect(try await runner.run(arguments: []).exitCode == 0)

        try probe.tamper()
        await #expect(throws: FlashError.bundleSealBroken) {
            try await runner.run(arguments: [])
        }
    }
}
