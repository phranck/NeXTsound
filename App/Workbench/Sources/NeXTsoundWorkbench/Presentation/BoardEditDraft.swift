import Foundation
import NeXTsoundCore

/// The edit form's values for the connected SoundBox: its name and its owner metadata, as the owner types them.
struct BoardEditDraft: Equatable {
    var name: String
    var owner: String
    /// The digits after the prefix NXSB. Empty means the board carries no number.
    var unitDigits: String
    var hasDate: Bool
    var date: Date
    var note: String

    /// The board's current values, with the register's proposal in place of a number the board does not carry yet,
    /// and today in place of a date it does not carry yet.
    init(
        capabilities: DeviceCapabilities,
        metadata: OwnerMetadata,
        proposedNumber: UInt32,
        calendar: Calendar = .current,
        today: Date = .now
    ) {
        name = capabilities.deviceName
        owner = metadata.owner
        unitDigits = SerialNumberFormat.digits(metadata.serialNumber ?? proposedNumber)
        hasDate = metadata.date != nil
        date = metadata.date.flatMap { day in
            calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
        } ?? today
        note = metadata.note
    }
}

/// One thing that keeps a draft from being written, or that the form warns about.
enum BoardEditProblem: Equatable {
    case invalidName
    case ownerTooLong
    case noteTooLong
    case invalidText
    case invalidNumber
    /// The register cannot be read, so a number could already belong to another board.
    case registerUnavailable
    case numberTaken(number: UInt32, chip: String)
    case numberLeavesGap(lowestFree: UInt32)
}

extension BoardEditDraft {
    /// The metadata the draft writes, or nil while the digits stand for no number.
    func metadata(calendar: Calendar = .current) -> OwnerMetadata? {
        var number: UInt32?
        if !unitDigits.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let parsed = SerialNumberFormat.number(in: unitDigits) else {
                return nil
            }
            number = parsed
        }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = hasDate ? CalendarDay(year: components.year ?? 0, month: components.month ?? 0, day: components.day ?? 0) : nil
        return OwnerMetadata(date: day, serialNumber: number, owner: owner, note: note)
    }

    /// Everything that keeps the draft from being written or that the owner should know first, in the form's order.
    /// The text rules are the shared codec's, so the form refuses what the board would refuse.
    func problems(register: SerialNumberRegister?, chip: String, calendar: Calendar = .current) -> [BoardEditProblem] {
        var problems: [BoardEditProblem] = []
        if (try? WireCodec.encodeDeviceName(name)) == nil {
            problems.append(.invalidName)
        }
        let ownerTooLong = owner.utf8.count > OwnerMetadata.ownerByteLimit
        let noteTooLong = note.utf8.count > OwnerMetadata.noteByteLimit
        if ownerTooLong {
            problems.append(.ownerTooLong)
        }
        if noteTooLong {
            problems.append(.noteTooLong)
        }
        guard let metadata = metadata(calendar: calendar) else {
            return problems + [.invalidNumber]
        }
        if !ownerTooLong, !noteTooLong, (try? WireCodec.encodeOwnerMetadata(metadata)) == nil {
            problems.append(.invalidText)
        }
        guard let number = metadata.serialNumber else {
            return problems
        }
        guard let register else {
            return problems + [.registerUnavailable]
        }
        switch register.problem(giving: number, to: chip) {
        case let .taken(holder): problems.append(.numberTaken(number: number, chip: holder))
        case let .leavesGap(lowest): problems.append(.numberLeavesGap(lowestFree: lowest))
        case nil: break
        }
        return problems
    }
}

extension BoardEditProblem {
    /// Whether the problem keeps the draft from being written. A gap only earns a warning, because the owner may skip a
    /// number on purpose.
    var blocksWriting: Bool {
        if case .numberLeavesGap = self {
            return false
        }
        return true
    }

    var message: String {
        switch self {
        case .invalidName:
            String(localized: "The name takes up to 31 letters, digits and punctuation marks, without accents.")
        case .ownerTooLong:
            String(localized: "The owner takes up to 64 bytes. An accented letter takes two.")
        case .noteTooLong:
            String(localized: "The note takes up to 256 bytes. An accented letter takes two.")
        case .invalidText:
            String(localized: "The owner and the note cannot contain control characters, and the owner no line breaks.")
        case .invalidNumber:
            String(localized: "The number takes digits from 0 to \(String(OwnerMetadata.maximumSerialNumber)).")
        case .registerUnavailable:
            String(localized: "The serial-number register cannot be read, so a number could already belong to another SoundBox.")
        case let .numberTaken(number, chip):
            String(localized: "\(SerialNumberFormat.text(number)) already belongs to the SoundBox \(chip).")
        case let .numberLeavesGap(lowest):
            String(localized: "\(SerialNumberFormat.text(lowest)) is still free.")
        }
    }
}
