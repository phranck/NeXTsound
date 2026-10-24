import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct SerialNumberRegisterTests {
    @Test func theFirstBoardGetsNumberOne() {
        #expect(SerialNumberRegister().proposal(for: "CHIP-A") == 1)
    }

    /// NXSB0000 is the owner's test number: a board may carry it, it is never proposed, and it opens no gap.
    @Test func theTestNumberIsAllowedButNotProposed() {
        let register = SerialNumberRegister(numbers: ["TEST": 0])
        #expect(register.proposal(for: "CHIP-A") == 1)
        #expect(SerialNumberRegister().problem(giving: 0, to: "TEST") == nil)
        #expect(register.problem(giving: 0, to: "CHIP-A") == .taken(chip: "TEST"))
    }

    @Test func aBoardKeepsItsNumberAndOthersGetTheLowestFreeOne() {
        let register = SerialNumberRegister(numbers: ["CHIP-A": 1, "CHIP-B": 2, "CHIP-D": 4])
        #expect(register.proposal(for: "CHIP-B") == 2)
        #expect(register.proposal(for: "CHIP-C") == 3)
    }

    @Test func aNumberAnotherBoardCarriesIsTaken() {
        let register = SerialNumberRegister(numbers: ["CHIP-A": 1])
        #expect(register.problem(giving: 1, to: "CHIP-B") == .taken(chip: "CHIP-A"))
        #expect(register.problem(giving: 1, to: "CHIP-A") == nil)
    }

    @Test func aNumberAboveTheLowestFreeOneLeavesAGap() {
        let register = SerialNumberRegister(numbers: ["CHIP-A": 1, "CHIP-C": 3])
        #expect(register.problem(giving: 4, to: "CHIP-B") == .leavesGap(lowestFree: 2))
        #expect(register.problem(giving: 2, to: "CHIP-B") == nil)
        #expect(register.problem(giving: 3, to: "CHIP-C") == nil)
    }

    @Test func aConnectedBoardsNumberIsAdoptedUnlessAnotherBoardHoldsIt() {
        var register = SerialNumberRegister(numbers: ["CHIP-A": 1])
        let adoptedNew = register.adopt(2, from: "CHIP-B")
        let adoptedAgain = register.adopt(2, from: "CHIP-B")
        let adoptedTaken = register.adopt(1, from: "CHIP-C")
        #expect(adoptedNew && !adoptedAgain && !adoptedTaken)
        #expect(register.numbers == ["CHIP-A": 1, "CHIP-B": 2])
    }

    @Test func assigningNothingRemovesTheBoard() {
        var register = SerialNumberRegister(numbers: ["CHIP-A": 1])
        register.assign(nil, to: "CHIP-A")
        #expect(register.numbers.isEmpty)
    }

    @Test func theStoredRegisterRoundTripsAndRefusesWhatTheBoardCannotStore() throws {
        let register = SerialNumberRegister(numbers: ["TEST": 0, "CHIP-A": 1, "CHIP-B": OwnerMetadata.maximumSerialNumber])
        #expect(try SerialNumberRegister.decode(register.encoded()) == register)
        #expect(throws: (any Error).self) {
            try SerialNumberRegister.decode(Data(#"{"formatVersion":1,"numbers":{"CHIP-A":16777216}}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try SerialNumberRegister.decode(Data(#"{"formatVersion":2,"numbers":{}}"#.utf8))
        }
    }

    @Test func numbersReadWithThePrefixAndAtLeastFourDigits() {
        #expect(SerialNumberFormat.text(1) == "NXSB0001")
        #expect(SerialNumberFormat.text(123_456) == "NXSB123456")
        #expect(SerialNumberFormat.number(in: "0042") == 42)
        #expect(SerialNumberFormat.number(in: "nxsb0042") == 42)
        #expect(SerialNumberFormat.number(in: "0") == 0)
        #expect(SerialNumberFormat.number(in: "NXSB0000") == 0)
        #expect(SerialNumberFormat.text(0) == "NXSB0000")
        #expect(SerialNumberFormat.number(in: "") == nil)
        #expect(SerialNumberFormat.number(in: "4a") == nil)
        #expect(SerialNumberFormat.number(in: "16777216") == nil)
        #expect(SerialNumberFormat.number(in: "١٢") == nil)
    }
}

struct SerialNumberRegisterStoreTests {
    @Test func aMissingFileLoadsAsNoRegisterAndASavedOneRoundTrips() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SerialNumberRegisterStore(fileURL: url)
        #expect(try await store.load() == nil)
        let register = SerialNumberRegister(numbers: ["CHIP-A": 1])
        try await store.save(register)
        #expect(try await SerialNumberRegisterStore(fileURL: url).load() == register)
    }
}
