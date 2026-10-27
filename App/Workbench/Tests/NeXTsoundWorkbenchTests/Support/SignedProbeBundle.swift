import Foundation
import Testing

/// A minimal app bundle in a temporary directory, signed ad hoc like the built app, so `BundleSeal` accepts it until a
/// sealed file changes.
///
/// Tests that start a real `ProcessPicotoolRunner` pass this bundle as its app bundle. Left at its default, the runner
/// checks `Bundle.main`, which in a test process is the test host inside Xcode, and checking all of Xcode never ends in
/// practice. The executable is a copy of `/usr/bin/true`, which only has to be a Mach-O file for `codesign` to sign the
/// bundle; the `picotool` resource is whatever the test asks for.
struct SignedProbeBundle {
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

    /// - Parameters:
    ///   - picotool: The contents of the `picotool` resource, by default a shell script that exits at once.
    ///   - picotoolIsExecutable: Whether the resource may be started.
    init(picotool: Data = Data("#!/bin/sh\nexit 0\n".utf8), picotoolIsExecutable: Bool = true) throws {
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
        try fileManager.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: contents.appendingPathComponent("MacOS/Probe"))
        let resource = contents.appendingPathComponent("Resources/picotool")
        try picotool.write(to: resource)
        try fileManager.setAttributes([.posixPermissions: picotoolIsExecutable ? 0o755 : 0o644], ofItemAtPath: resource.path)
        try Self.sign(url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private extension SignedProbeBundle {
    static func sign(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", url.path]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }
}
