import Foundation
import Testing
@testable import NeXTsoundCore

struct DriverLibraryTests {
    @Test func aFreshLibraryIsSeededWithTheKnownCandidates() {
        let library = DriverLibrary()
        #expect(library.drivers.count == DriverLibrary.knownCandidates.count)
        #expect(library.drivers.contains { $0.model == "TEBM28C10-4" })
    }

    @Test func aLibraryWithNoDriversIsRejected() {
        #expect(throws: DriverLibraryError.invalidLibrary) { try DriverLibrary(drivers: []) }
    }

    @Test func duplicateDriverIDsAreRejected() {
        let driver = DriverRecord()
        #expect(throws: DriverLibraryError.invalidLibrary) { try DriverLibrary(drivers: [driver, driver]) }
    }

    @Test func insertingAddsANewDriver() throws {
        var library = DriverLibrary()
        let before = library.drivers.count
        let driver = DriverRecord(name: "Second driver")
        try library.insert(driver)
        #expect(library.drivers.count == before + 1)
    }

    @Test func insertingADuplicateIdentifierIsRejected() {
        var library = DriverLibrary()
        let duplicate = library.drivers[0]
        #expect(throws: DriverLibraryError.duplicateDriver) { try library.insert(duplicate) }
    }

    @Test func updatingReplacesTheMatchingEntry() throws {
        var library = DriverLibrary()
        var driver = library.drivers[0]
        driver.notes = "Edited"
        try library.update(driver)
        #expect(library.drivers[0].notes == "Edited")
    }

    @Test func updatingAnUnknownDriverIsRejected() {
        var library = DriverLibrary()
        #expect(throws: DriverLibraryError.driverNotFound) { try library.update(DriverRecord(name: "Unknown")) }
    }

    @Test func removingTheLastDriverIsRejected() throws {
        var library = try DriverLibrary(drivers: [DriverRecord()])
        #expect(throws: DriverLibraryError.lastDriver) { try library.remove(library.drivers[0].id) }
    }

    @Test func removingAnUnknownDriverIsRejected() {
        var library = DriverLibrary()
        #expect(throws: DriverLibraryError.driverNotFound) { try library.remove(UUID()) }
    }

    @Test func removingLeavesTheRemainingDrivers() throws {
        var library = DriverLibrary()
        let before = library.drivers.count
        let first = library.drivers[0]
        let second = DriverRecord(name: "Second driver")
        try library.insert(second)
        try library.remove(first.id)
        #expect(library.drivers.count == before)
        #expect(!library.drivers.contains { $0.id == first.id })
        #expect(library.drivers.contains { $0.id == second.id })
    }

    @Test func aLibraryRoundTripsThroughJSON() throws {
        let library = DriverLibrary()
        #expect(try DriverLibrary.decode(library.encoded()) == library)
    }

    @Test func anInvalidEntryFailsLibraryValidation() {
        let invalid = DriverRecord(name: "   ")
        #expect(throws: DriverValidationError.missingName) { try DriverLibrary(drivers: [invalid]) }
    }
}
