import Foundation

/// Runs the picotool binary embedded as a package resource (`Scripts/bootstrap-picotool-usb.sh`
/// builds it with libusb linked in). The app never depends on a system picotool install.
///
/// Every run first checks the app bundle's seal, because picotool writes firmware onto the board and a replaced
/// picotool or firmware image would run with everything the app is allowed to do.
struct ProcessPicotoolRunner: PicotoolRunning {
    private let executableURL: URL
    private let appBundleURL: URL

    /// - Parameters:
    ///   - bundle: The resource bundle holding `picotool`.
    ///   - appBundleURL: The signed app bundle whose seal covers `picotool` and the firmware image.
    init?(bundle: Bundle = .module, appBundleURL: URL = Bundle.main.bundleURL) {
        guard let url = bundle.url(forResource: "picotool", withExtension: nil) else {
            return nil
        }
        executableURL = url
        self.appBundleURL = appBundleURL
    }
}

extension ProcessPicotoolRunner {
    func run(arguments: [String]) async throws -> (exitCode: Int32, output: String) {
        try BundleSeal.verify(appBundleURL)
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        async let collectedOutput = Self.drain(pipe)
        let exitCode: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                // A started process takes over the pipe's write end. One that never started leaves it open here, so
                // the output reader would wait for an end of file that never comes.
                try? pipe.fileHandleForWriting.close()
                continuation.resume(throwing: error)
            }
        }
        return try await (exitCode, collectedOutput)
    }
}

private extension ProcessPicotoolRunner {
    static func drain(_ pipe: Pipe) async throws -> String {
        var output = ""
        for try await line in pipe.fileHandleForReading.bytes.lines {
            output += line + "\n"
        }
        return output
    }
}
