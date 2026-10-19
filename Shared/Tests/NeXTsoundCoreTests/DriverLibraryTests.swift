import Foundation
import Testing
@testable import NeXTsoundCore

struct DriverLibraryTests {
    @Test func aFreshLibraryIsSeededWithTheOwnersOnlyDriver() {
        let library = DriverLibrary()
        #expect(library.drivers.count == 1)
        #expect(library.drivers[0].model == "TEBM28C10-4")
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
        let driver = DriverRecord(name: "Second driver")
        try library.insert(driver)
        #expect(library.drivers.count == 2)
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

    @Test func removingTheLastDriverIsRejected() {
        var library = DriverLibrary()
        #expect(throws: DriverLibraryError.lastDriver) { try library.remove(library.drivers[0].id) }
    }

    @Test func removingAnUnknownDriverIsRejected() {
        var library = DriverLibrary()
        #expect(throws: DriverLibraryError.driverNotFound) { try library.remove(UUID()) }
    }

    @Test func removingLeavesTheRemainingDrivers() throws {
        var library = DriverLibrary()
        let second = DriverRecord(name: "Second driver")
        try library.insert(second)
        try library.remove(library.drivers[0].id)
        #expect(library.drivers.count == 1)
        #expect(library.drivers[0].id == second.id)
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
