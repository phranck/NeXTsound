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

/// A minimal app bundle in a temporary directory, signed ad hoc like the built app. Its executable and its `picotool`
/// resource is a shell script that exits at once, so the runner can start it without touching a board. The executable
/// is a copy of `/usr/bin/true`, which only has to be a Mach-O file for `codesign` to sign the bundle.
private struct SignedProbeBundle {
    let directory: URL
    let url: URL

    var resourceURL: URL {
        url.appendingPathComponent("Contents/Resources/picotool")
    }

    var bundle: Bundle {
        get throws {
            try #require(Bundle(url: url))
        }
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("nxs-seal-\(UUID().uuidString)", isDirectory: true)
        url = directory.appendingPathComponent("Probe.app", isDirectory: true)
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "work.layered.NeXTsound.seal-probe",
            "CFBundleExecutable": "Probe",
            "CFBundlePackageType": "APPL",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let executable = URL(fileURLWithPath: "/usr/bin/true")
        try fileManager.copyItem(at: executable, to: contents.appendingPathComponent("MacOS/Probe"))
        let picotool = contents.appendingPathComponent("Resources/picotool")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: picotool)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: picotool.path)
        try Self.sign(url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func sign(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", url.path]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }
}
