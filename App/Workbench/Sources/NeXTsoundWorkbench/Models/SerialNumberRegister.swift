import Foundation
import NeXTsoundCore

/// The serial numbers the app has written to boards, each under the chip serial of the board that carries it, so that
/// no number goes to two boards and none is skipped by accident.
public struct SerialNumberRegister: Equatable, Sendable {
    /// The largest stored register the store reads.
    static let maximumFileBytes = 1_048_576
    /// The version of the stored register's format.
    static let formatVersion = 1

    /// The number of each board, by the chip serial its capabilities report.
    public private(set) var numbers: [String: UInt32]

    public init(numbers: [String: UInt32] = [:]) {
        self.numbers = numbers
    }
}

/// Why a serial number may not, or should not, go to a board.
public enum SerialNumberProblem: Equatable, Sendable {
    /// Another board, named by its chip serial, already carries the number.
    case taken(chip: String)
    /// A lower number is still free, so the number would leave a gap; the lowest free one is given.
    case leavesGap(lowestFree: UInt32)
}

public extension SerialNumberRegister {
    /// The number the board carries according to the register, or the lowest one no other board carries.
    func proposal(for chip: String) -> UInt32 {
        numbers[chip] ?? lowestFree(excluding: chip)
    }

    /// What speaks against giving `number` to the board with `chip`, or nil when nothing does.
    func problem(giving number: UInt32, to chip: String) -> SerialNumberProblem? {
        if let holder = holder(of: number, excluding: chip) {
            return .taken(chip: holder)
        }
        // A board that keeps the number it has opens no new gap.
        if numbers[chip] == number {
            return nil
        }
        let lowest = lowestFree(excluding: chip)
        return number > lowest ? .leavesGap(lowestFree: lowest) : nil
    }

    /// Records the number a board was given, or removes the board's entry when the number was cleared.
    mutating func assign(_ number: UInt32?, to chip: String) {
        numbers[chip] = number
    }

    /// Records the number a connected board reports, unless another board holds it in the register. Returns whether
    /// the register changed, so the caller saves it only then.
    mutating func adopt(_ number: UInt32, from chip: String) -> Bool {
        guard
            numbers[chip] != number,
            holder(of: number, excluding: chip) == nil
        else {
            return false
        }
        numbers[chip] = number
        return true
    }

    /// The register as the store writes it.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(StoredRegister(formatVersion: Self.formatVersion, numbers: numbers))
    }

    /// Reads a stored register, refusing an unknown format version and numbers the board cannot store.
    static func decode(_ data: Data) throws -> SerialNumberRegister {
        let stored = try JSONDecoder().decode(StoredRegister.self, from: data)
        guard
            stored.formatVersion == formatVersion,
            stored.numbers.values.allSatisfy({ (0 ... OwnerMetadata.maximumSerialNumber).contains($0) })
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return SerialNumberRegister(numbers: stored.numbers)
    }
}

private extension SerialNumberRegister {
    struct StoredRegister: Codable {
        let formatVersion: Int
        let numbers: [String: UInt32]
    }

    func holder(of number: UInt32, excluding chip: String) -> String? {
        numbers.first { $0.key != chip && $0.value == number }?.key
    }

    /// Starts at 1, because NXSB0000 is the owner's test number, given by hand rather than proposed.
    func lowestFree(excluding chip: String) -> UInt32 {
        let taken = Set(numbers.filter { $0.key != chip }.values)
        var candidate: UInt32 = 1
        while taken.contains(candidate) {
            candidate += 1
        }
        return candidate
    }
}

/// How the app writes a serial number: the prefix NXSB and at least four digits, so the board's first one reads
/// NXSB0001.
enum SerialNumberFormat {
    static let prefix = "NXSB"

    static func text(_ number: UInt32) -> String {
        prefix + digits(number)
    }

    /// The digits after the prefix, at least four.
    static func digits(_ number: UInt32) -> String {
        let plain = String(number)
        return String(repeating: "0", count: max(0, 4 - plain.count)) + plain
    }

    /// The number that digits, with or without the prefix, stand for, or nil when they do not stand for one from 0 to
    /// `OwnerMetadata.maximumSerialNumber`.
    static func number(in text: String) -> UInt32? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.uppercased().hasPrefix(prefix) ? String(trimmed.dropFirst(prefix.count)) : trimmed
        guard
            !digits.isEmpty,
            digits.allSatisfy(\.isASCII),
            let number = UInt32(digits),
            (0 ... OwnerMetadata.maximumSerialNumber).contains(number)
        else {
            return nil
        }
        return number
    }
}
