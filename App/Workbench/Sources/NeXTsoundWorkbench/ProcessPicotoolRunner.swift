import Foundation

/// Runs the picotool binary embedded as a package resource (`Scripts/bootstrap-picotool-usb.sh`
/// builds it against Homebrew's libusb). The app never depends on a system picotool install.
struct ProcessPicotoolRunner: PicotoolRunning {
    private let executableURL: URL

    init?(bundle: Bundle = .module) {
        guard let url = bundle.url(forResource: "picotool", withExtension: nil) else {
            return nil
        }
        executableURL = url
    }
}

extension ProcessPicotoolRunner {
    func run(arguments: [String]) async throws -> (exitCode: Int32, output: String) {
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
