import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct BoardEditDraftTests {
    @Test func aBoardWithoutANumberStartsWithTheRegistersProposal() {
        let draft = draft(OwnerMetadata(), proposedNumber: 3)
        #expect(draft.unitDigits == "0003" && !draft.hasDate)
        #expect(draft.metadata(calendar: calendar)?.serialNumber == 3)
    }

    @Test func theBoardsValuesRoundTripThroughTheDraft() {
        let metadata = OwnerMetadata(
            date: CalendarDay(year: 2026, month: 10, day: 24),
            serialNumber: 7,
            owner: "Jürgen",
            note: "First line\nSecond line"
        )
        let draft = draft(metadata, proposedNumber: 1)
        #expect(draft.name == "Bedroom SoundBox" && draft.unitDigits == "0007" && draft.hasDate)
        #expect(draft.metadata(calendar: calendar) == metadata)
        #expect(draft.problems(register: SerialNumberRegister(numbers: [chip: 7]), chip: chip, calendar: calendar).isEmpty)
    }

    @Test func clearingTheDigitsClearsTheNumber() {
        var draft = draft(OwnerMetadata(serialNumber: 7), proposedNumber: 1)
        draft.unitDigits = ""
        #expect(draft.metadata(calendar: calendar)?.serialNumber == nil)
        #expect(draft.problems(register: nil, chip: chip, calendar: calendar).isEmpty)
    }

    @Test func whatTheBoardRefusesBlocksWriting() {
        var draft = draft(OwnerMetadata(), proposedNumber: 1)
        draft.name = "Küche"
        draft.owner = String(repeating: "ä", count: 33)
        draft.note = "Tab\t"
        let problems = draft.problems(register: SerialNumberRegister(), chip: chip, calendar: calendar)
        #expect(problems == [.invalidName, .ownerTooLong])
        draft.owner = "Owner"
        #expect(draft.problems(register: SerialNumberRegister(), chip: chip, calendar: calendar) == [.invalidName, .invalidText])
        draft.note = String(repeating: "n", count: 257)
        #expect(draft.problems(register: SerialNumberRegister(), chip: chip, calendar: calendar) == [.invalidName, .noteTooLong])
        let allBlock = draft.problems(register: SerialNumberRegister(), chip: chip, calendar: calendar).allSatisfy(\.blocksWriting)
        #expect(allBlock)
    }

    @Test func theNumberIsCheckedAgainstTheRegister() {
        var draft = draft(OwnerMetadata(), proposedNumber: 1)
        let register = SerialNumberRegister(numbers: ["OTHER": 1])
        #expect(draft.problems(register: register, chip: chip, calendar: calendar) == [.numberTaken(number: 1, chip: "OTHER")])
        draft.unitDigits = "0003"
        let gap = draft.problems(register: register, chip: chip, calendar: calendar)
        #expect(gap == [.numberLeavesGap(lowestFree: 2)] && !gap[0].blocksWriting)
        #expect(draft.problems(register: nil, chip: chip, calendar: calendar) == [.registerUnavailable])
        draft.unitDigits = "abc"
        #expect(draft.metadata(calendar: calendar) == nil)
        #expect(draft.problems(register: register, chip: chip, calendar: calendar) == [.invalidNumber])
    }
}

private extension BoardEditDraftTests {
    var chip: String {
        "D4CDD489AFE28CC5"
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        return calendar
    }

    func draft(_ metadata: OwnerMetadata, proposedNumber: UInt32) -> BoardEditDraft {
        var capabilities = fixtureCapabilities(serial: chip)
        capabilities.deviceName = "Bedroom SoundBox"
        return BoardEditDraft(capabilities: capabilities, metadata: metadata, proposedNumber: proposedNumber, calendar: calendar)
    }
}
