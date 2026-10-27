import Foundation
import Testing
@testable import NeXTsoundWorkbench

struct BundleSealTests {
    @Test func anUnchangedSignedBundlePasses() throws {
        let probe = try SignedProbeBundle()
        defer { probe.remove() }
        try BundleSeal.verify(probe.url)
    }

    @Test func aChangedResourceBreaksTheSeal() throws {
        let probe = try SignedProbeBundle()
        defer { probe.remove() }
        try Data("replaced".utf8).write(to: probe.resourceURL)
        #expect(throws: FlashError.bundleSealBroken) {
            try BundleSeal.verify(probe.url)
        }
    }

    @Test func theRunnerRefusesPicotoolFromATamperedBundle() async throws {
        let probe = try SignedProbeBundle()
        defer { probe.remove() }
        let runner = try #require(ProcessPicotoolRunner(bundle: probe.bundle, appBundleURL: probe.url))
        #expect(try await runner.run(arguments: []).exitCode == 0)

        try Data("replaced".utf8).write(to: probe.resourceURL)
        await #expect(throws: FlashError.bundleSealBroken) {
            try await runner.run(arguments: [])
        }
    }
}
