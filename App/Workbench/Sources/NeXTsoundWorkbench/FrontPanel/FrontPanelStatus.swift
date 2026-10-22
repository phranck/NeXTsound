import Foundation
import NeXTsoundCore

/// What the status column at the right of the multifunction display shows.
///
/// The connection stands on its first line, a verified board's metadata and live values below it, and the latest
/// message on the bottom line, level with the profile's name. A board that is not verified has reported nothing, so
/// it shows no value lines, which leaves the message room to wrap upward.
struct FrontPanelStatus: Equatable {
    var connection: String
    var fields: [FrontPanelStatusField]
    var message: FrontPanelMessage?
}

/// One line of the status column: a label one brightness step below its value, so the column reads as a table.
struct FrontPanelStatusField: Equatable {
    let label: String
    let value: String
}

/// The message on the display's bottom line.
struct FrontPanelMessage: Equatable {
    let text: String
    var isError = false
    var tone = DotMatrixTone.bright
}

extension FrontPanelStatus {
    /// The column for a board's connection, storage and live values, and the message to show under them.
    init(board: BoardConnectionState, storage: BoardStorageState, runtime: DeviceRuntimeStatus?, message: FrontPanelMessage?) {
        connection = board.title
        fields = Self.fields(board: board, storage: storage, runtime: runtime)
        self.message = message
    }
}

private extension FrontPanelStatus {
    static let bytesPerMegabyte: UInt32 = 1_048_576
    static let displayLocale = Locale(identifier: "en_US_POSIX")

    /// The flash memory line's label. It has a key of its own, because the catalog's "Flash" is the verb on the flash
    /// sheet's button.
    static var flashLabel: String {
        String(
            localized: "Flash (memory)",
            defaultValue: "Flash",
            comment: "Label of the flash memory line in the front panel's status column."
        )
    }

    static func fields(board: BoardConnectionState, storage: BoardStorageState, runtime: DeviceRuntimeStatus?) -> [FrontPanelStatusField] {
        guard case let .verified(capabilities) = board else {
            return []
        }
        var fields = [
            FrontPanelStatusField(label: String(localized: "Name"), value: capabilities.deviceName),
            FrontPanelStatusField(label: String(localized: "Serial"), value: capabilities.serial),
            FrontPanelStatusField(label: String(localized: "FW"), value: capabilities.firmwareVersion),
            FrontPanelStatusField(label: String(localized: "Audio"), value: audio(capabilities)),
            FrontPanelStatusField(label: flashLabel, value: flash(capabilities, storage: storage)),
        ]
        if let runtime {
            fields.append(FrontPanelStatusField(label: String(localized: "Host"), value: host(runtime)))
            fields.append(FrontPanelStatusField(label: String(localized: "DSP"), value: processing(runtime)))
        }
        return fields
    }

    static func audio(_ capabilities: DeviceCapabilities) -> String {
        let kilohertz = Int(capabilities.sampleRateHz / 1000)
        let bits = capabilities.sampleBits.map(String.init).joined(separator: "/")
        return String(localized: "\(kilohertz) kHz \(bits) bit")
    }

    static func flash(_ capabilities: DeviceCapabilities, storage: BoardStorageState) -> String {
        let megabytes = Int(capabilities.flashSizeBytes / bytesPerMegabyte)
        switch storage {
        case .unknown: return String(localized: "\(megabytes) MB")
        case .saved: return String(localized: "\(megabytes) MB saved")
        case .unsaved: return String(localized: "\(megabytes) MB not saved")
        case .unavailable: return String(localized: "\(megabytes) MB no storage")
        }
    }

    static func host(_ runtime: DeviceRuntimeStatus) -> String {
        if runtime.hostIsMuted {
            return String(localized: "muted")
        }
        let volume = String(format: "%.1f", locale: displayLocale, runtime.hostVolumeDb)
        return runtime.isStreaming ? String(localized: "playing \(volume) dB") : String(localized: "idle \(volume) dB")
    }

    /// The share of the block deadline the audio processing took at most, and the underruns and overruns since start.
    static func processing(_ runtime: DeviceRuntimeStatus) -> String {
        let deadline = Double(runtime.blockDeadlineUs)
        let load = deadline > 0 ? Int((100 * Double(runtime.maxProcessingUs) / deadline).rounded()) : 0
        return String(localized: "\(load)% xrun \(Int(runtime.underrunCount))/\(Int(runtime.overrunCount))")
    }
}

/// Everything the display's message line reports, and the one message it shows.
///
/// The first of these that has something to say wins: a save that runs or has just finished, a board or profile
/// error, the profile's validation problem, the library's storage status, and the reminder that a verified board
/// plays every edit.
struct FrontPanelMessageSources: Equatable {
    /// What the model says while a save to the SoundBox runs.
    var saveInProgress: String?
    /// Whether a save to the SoundBox finished a moment ago.
    var saveSucceeded = false
    /// A board or profile error the model reports.
    var error: String?
    var board: BoardConnectionState = .disconnected
    var validationProblem: String?
    var storageStatus: String?
    /// Whether the storage status reports a failure.
    var storageFailed = false
}

extension FrontPanelMessageSources {
    var message: FrontPanelMessage? {
        if let saveInProgress {
            return FrontPanelMessage(text: saveInProgress)
        }
        if saveSucceeded {
            return FrontPanelMessage(text: String(localized: "Settings saved"))
        }
        if let error {
            return FrontPanelMessage(text: error, isError: true)
        }
        if case let .mismatched(reason) = board {
            return FrontPanelMessage(text: reason, isError: true)
        }
        if let validationProblem {
            return FrontPanelMessage(text: validationProblem, isError: true)
        }
        if let storageStatus {
            return FrontPanelMessage(text: storageStatus, isError: storageFailed, tone: storageFailed ? .bright : .normal)
        }
        if case .verified = board {
            return FrontPanelMessage(text: String(localized: "Edits play live"), tone: .normal)
        }
        return nil
    }
}
