import Foundation
import NeXTsoundCore

enum FlashPhase: Sendable, Equatable {
    case waitingForBootloader
    case writingAndVerifying
    case restartingApplication
}

extension FlashPhase {
    var statusText: String {
        switch self {
        case .waitingForBootloader: String(localized: "waiting for the board to appear in BOOTSEL mode")
        case .writingAndVerifying: String(localized: "writing and verifying the firmware image")
        case .restartingApplication: String(localized: "restarting the application firmware")
        }
    }
}

enum FlashError: Error, LocalizedError, Equatable {
    case picotoolUnavailable
    case firmwareUnavailable
    case timedOut(FlashPhase)
    case commandFailed(FlashPhase, String)

    var errorDescription: String? {
        switch self {
        case .picotoolUnavailable:
            String(localized: "The embedded picotool tool is missing from the app bundle.")
        case .firmwareUnavailable:
            String(localized: "The embedded firmware image is missing from the app bundle.")
        case let .timedOut(phase):
            String(localized: "Timed out \(phase.statusText).")
        case let .commandFailed(phase, output):
            String(localized: "Failed while \(phase.statusText): \(output)")
        }
    }
}

struct FlashTarget: Sendable, Equatable {
    /// The serial of the board's currently-running application firmware, when one is connected and
    /// verified. `FlashService` then force-reboots that exact board into BOOTSEL by serial before
    /// flashing; otherwise the board must already be in BOOTSEL mode (held into it by hand).
    var applicationSerial: String?

    init(applicationSerial: String? = nil) {
        self.applicationSerial = applicationSerial
    }
}

protocol PicotoolRunning: Sendable {
    func run(arguments: [String]) async throws -> (exitCode: Int32, output: String)
}

struct FlashService: Sendable {
    /// The RP-series ROM bootloader's own USB identity in BOOTSEL mode, fixed by the chip's boot ROM
    /// rather than by NeXTsound's firmware; see `Documentation/Backup.md`'s observed specimen.
    static let bootloaderVendorID = 0x2E8A
    static let bootloaderProductID = 0x000F

    private let runner: any PicotoolRunning
    private let pollInterval: Duration
    private let bootloaderTimeout: Duration

    init(runner: any PicotoolRunning, pollInterval: Duration = .milliseconds(250), bootloaderTimeout: Duration = .seconds(15)) {
        self.runner = runner
        self.pollInterval = pollInterval
        self.bootloaderTimeout = bootloaderTimeout
    }
}

extension FlashService {
    /// Flashes `firmwareURL` onto `target` and verifies it by readback, then reboots into it.
    /// Never reboots into the newly written image when writing or verifying failed.
    func flash(_ firmwareURL: URL, target: FlashTarget, onPhase: @Sendable (FlashPhase) -> Void) async throws {
        if let serial = target.applicationSerial {
            onPhase(.writingAndVerifying)
            try await run(.writingAndVerifying, [
                "load",
                "-v",
                "-F",
                "--vid",
                Self.hex(BoardIdentity.vendorID),
                "--pid",
                Self.hex(BoardIdentity.productID),
                "--ser",
                serial,
                firmwareURL.path,
            ])
        } else {
            onPhase(.waitingForBootloader)
            try await waitForBootloader()
            onPhase(.writingAndVerifying)
            try await run(.writingAndVerifying, ["load", "-v"] + deviceFilter(serial: nil) + [firmwareURL.path])
        }
        onPhase(.restartingApplication)
        try await run(.restartingApplication, ["reboot"] + deviceFilter(serial: target.applicationSerial))
    }
}

private extension FlashService {
    func waitForBootloader() async throws {
        let deadline = ContinuousClock.now + bootloaderTimeout
        while true {
            let (exitCode, _) = try await runner.run(arguments: ["info", "-d"] + deviceFilter(serial: nil))
            if exitCode == 0 {
                return
            }
            if ContinuousClock.now >= deadline {
                throw FlashError.timedOut(.waitingForBootloader)
            }
            try await Task.sleep(for: pollInterval)
        }
    }

    func run(_ phase: FlashPhase, _ arguments: [String]) async throws {
        let (exitCode, output) = try await runner.run(arguments: arguments)
        guard exitCode == 0 else {
            throw FlashError.commandFailed(phase, output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// After a forced reboot, the board must be addressed by serial alone: the ROM bootloader's
    /// VID/PID can be white-labelled on RP2350, but its serial never changes. Without a known
    /// serial, the fixed BOOTSEL VID/PID is the only filter available.
    func deviceFilter(serial: String?) -> [String] {
        if let serial {
            ["--ser", serial]
        } else {
            ["--vid", Self.hex(Self.bootloaderVendorID), "--pid", Self.hex(Self.bootloaderProductID)]
        }
    }

    static func hex(_ value: Int) -> String {
        String(format: "0x%x", value)
    }
}
