import Foundation
import Testing

/// A copy of the committed fixture `SealProbe.app`, an app bundle signed ad hoc like the built app, so `BundleSeal`
/// accepts it until a sealed file changes, and a resource bundle next to it holding the `picotool` a test asks for.
///
/// Tests that start a real `ProcessPicotoolRunner` pass `url` as its app bundle. Left at its default, the runner checks
/// `Bundle.main`, which in a test process is the test host inside Xcode. The fixture is signed once and committed,
/// because a test that ran `codesign` blocked a thread of the concurrency pool until it returned, and on the few cores
/// of a CI machine that froze the whole test run.
struct SignedProbeBundle {
    let directory: URL
    /// The signed app bundle.
    let url: URL
    /// The resource bundle holding `picotool`, which the seal does not cover.
    let resourceBundleURL: URL

    var bundle: Bundle {
        get throws {
            try #require(Bundle(url: resourceBundleURL))
        }
    }

    /// - Parameters:
    ///   - picotool: The contents of the `picotool` resource, by default a shell script that exits at once.
    ///   - picotoolIsExecutable: Whether the resource may be started.
    init(picotool: Data = Data("#!/bin/sh\nexit 0\n".utf8), picotoolIsExecutable: Bool = true) throws {
        let fileManager = FileManager.default
        directory = fileManager.temporaryDirectory.appendingPathComponent("nxs-seal-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = try #require(Bundle.module.url(forResource: "SealProbe", withExtension: "app"))
        url = directory.appendingPathComponent("SealProbe.app", isDirectory: true)
        try fileManager.copyItem(at: fixture, to: url)
        resourceBundleURL = directory.appendingPathComponent("Picotool.bundle", isDirectory: true)
        let resources = resourceBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
        let resource = resources.appendingPathComponent("picotool")
        try picotool.write(to: resource)
        try fileManager.setAttributes([.posixPermissions: picotoolIsExecutable ? 0o755 : 0o644], ofItemAtPath: resource.path)
    }

    /// Adds a file to the signed bundle's resources, which breaks its seal.
    func tamper() throws {
        try Data("tampered".utf8).write(to: url.appendingPathComponent("Contents/Resources/tampered.txt"))
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
