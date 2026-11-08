import Foundation
import NeXTsoundCore

/// What the status column at the right of the multifunction display shows.
///
/// The connection stands on its first line, and a verified board's identity, live values and owner details below it.
/// A board that is not verified has reported nothing, so it shows no value lines. The message is not part of the
/// column: the display's overlay shows it, as `FrontPanelMessageOverlay` decides.
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

/// A message the display's overlay shows.
struct FrontPanelMessage: Equatable {
    let text: String
    var isError = false
    var tone = DotMatrixTone.bright
    /// Whether the message stays while it is current, as a save in progress does, instead of leaving after a while.
    var isLasting = false
    /// Whether a click on the display dismisses the message. Its card shows an OK affordance then.
    var isDismissible = false
}

extension FrontPanelStatus {
    /// The defaults key of whether the status column stands in the display, which the front panel keeps across
    /// launches.
    static let visibilityStorageKey = "frontPanelShowsStatusColumn"

    /// The column for a board's connection, storage, live values and owner metadata, and the message for the overlay.
    init(
        board: BoardConnectionState,
        storage: BoardStorageState,
        runtime: DeviceRuntimeStatus?,
        metadata: OwnerMetadata? = nil,
        message: FrontPanelMessage?
    ) {
        connection = board.title
        fields = Self.fields(board: board, storage: storage, runtime: runtime, metadata: metadata)
        self.message = message
    }

    /// The column for the model's board, with the message that the model's state calls for. `saveSucceeded` says
    /// whether a save to the SoundBox finished a moment ago, which the front panel's save feedback knows, and
    /// `spectrumProblem` why the live spectrum cannot show the SoundBox's audio, which its monitor knows.
    @MainActor
    init(model: WorkbenchModel, saveSucceeded: Bool, spectrumProblem: String? = nil) {
        self.init(
            board: model.boards.state,
            storage: model.boards.storage,
            runtime: model.boards.runtime,
            metadata: model.boards.metadata,
            message: FrontPanelMessageSources(model: model, saveSucceeded: saveSucceeded, spectrumProblem: spectrumProblem).message
        )
    }

    /// What VoiceOver reads for the display: the profile, while the status column stands in the display the connection
    /// and every field, and the current message, which the overlay shows whether the column stands in it or not.
    func spokenDescription(profileName: String, showsStatus: Bool) -> String {
        let columnTexts = showsStatus ? [connection] + fields.map { "\($0.label) \($0.value)" } : []
        return ([profileName] + columnTexts + [message?.text].compactMap(\.self)).joined(separator: ". ")
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

    static func fields(
        board: BoardConnectionState,
        storage: BoardStorageState,
        runtime: DeviceRuntimeStatus?,
        metadata: OwnerMetadata?
    ) -> [FrontPanelStatusField] {
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
        if let metadata {
            fields += metadataFields(metadata)
        }
        return fields
    }

    /// A line for each owner field that is set. The note shows its first line.
    static func metadataFields(_ metadata: OwnerMetadata) -> [FrontPanelStatusField] {
        var fields: [FrontPanelStatusField] = []
        if !metadata.owner.isEmpty {
            let label = String(
                localized: "Owner",
                comment: "Label of the owner line in the front panel's status column, at most seven characters."
            )
            fields.append(FrontPanelStatusField(label: label, value: metadata.owner))
        }
        if let number = metadata.serialNumber {
            let label = String(
                localized: "Unit",
                comment: "Label of the serial number line in the front panel's status column, at most seven characters."
            )
            fields.append(FrontPanelStatusField(label: label, value: SerialNumberFormat.text(number)))
        }
        if let date = metadata.date {
            let label = String(
                localized: "Date",
                comment: "Label of the owner's date line in the front panel's status column, at most seven characters."
            )
            fields.append(FrontPanelStatusField(label: label, value: text(date)))
        }
        if let line = metadata.note.split(separator: "\n").first {
            let label = String(
                localized: "Note",
                comment: "Label of the note line in the front panel's status column, at most seven characters."
            )
            fields.append(FrontPanelStatusField(label: label, value: String(line)))
        }
        return fields
    }

    /// The day in the numeric order of the app's language, such as 24.10.2026.
    static func text(_ day: CalendarDay) -> String {
        let components = DateComponents(year: day.year, month: day.month, day: day.day)
        guard let date = Calendar(identifier: .gregorian).date(from: components) else {
            return ""
        }
        return date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
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

/// Everything the display's message overlay reports, and the one message that is current.
///
/// The first of these that has something to say wins: a save that runs or has just finished, a board or profile
/// error, the reason the live spectrum cannot show, the profile's validation problem, the library's storage status,
/// and the reminder that a verified board plays every edit.
struct FrontPanelMessageSources: Equatable {
    /// What the model says while a save to the SoundBox runs.
    var saveInProgress: String?
    /// Whether a save to the SoundBox finished a moment ago.
    var saveSucceeded = false
    /// A board or profile error the model reports.
    var error: String?
    var board: BoardConnectionState = .disconnected
    /// Why the live spectrum cannot show the SoundBox's audio.
    var spectrumProblem: String?
    var validationProblem: String?
    var storageStatus: String?
    /// A newer firmware release found by the app's one automatic check.
    var availableFirmwareUpdate: FirmwareRelease?
    /// Whether the storage status reports a failure.
    var storageFailed = false
}

extension FrontPanelMessageSources {
    /// The model's save, error, validation and storage news. `saveSucceeded` comes from the front panel's save
    /// feedback, because the model keeps no record of a save once it has finished, and `spectrumProblem` from the
    /// spectrum's monitor, which the model does not own.
    @MainActor
    init(model: WorkbenchModel, saveSucceeded: Bool, spectrumProblem: String? = nil) {
        self.init(
            saveInProgress: model.isSavingToBoard ? model.boardStorageStatus : nil,
            saveSucceeded: saveSucceeded,
            error: model.errorMessage,
            board: model.boards.state,
            spectrumProblem: spectrumProblem,
            validationProblem: model.profile.validationProblem,
            storageStatus: model.storageStatus,
            availableFirmwareUpdate: model.availableFirmwareUpdate,
            storageFailed: model.storageError != nil
        )
    }

    var message: FrontPanelMessage? {
        if let saveInProgress {
            return FrontPanelMessage(text: saveInProgress, isLasting: true)
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
        if let spectrumProblem {
            return FrontPanelMessage(text: spectrumProblem, isError: true)
        }
        if let validationProblem {
            return FrontPanelMessage(text: validationProblem, isError: true)
        }
        if let storageStatus {
            return FrontPanelMessage(text: storageStatus, isError: storageFailed, tone: storageFailed ? .bright : .normal)
        }
        if let availableFirmwareUpdate {
            let version = availableFirmwareUpdate.version.description
            return FrontPanelMessage(
                text: String(localized: "Firmware \(version) is available. Open FLASH to update."),
                isLasting: true,
                isDismissible: true
            )
        }
        if case .verified = board {
            return FrontPanelMessage(text: String(localized: "Edits play live"), tone: .normal)
        }
        return nil
    }
}
