import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct DriverModelSelectionTests {
    @Test func aSelectionCopiesItsDriverIntoTheDraft() throws {
        let library = try libraryWithTwoDrivers()
        var selection = DriverModelSelection()
        #expect(!selection.canDelete)
        selection.select(library.drivers[1].id, in: library.drivers)
        #expect(selection.draft == library.drivers[1])
        #expect(selection.canDelete)
        selection.select(nil, in: library.drivers)
        #expect(selection.draft == nil)
    }

    @Test func applyValidatesTheDraftBeforeItSaves() throws {
        let library = try libraryWithTwoDrivers()
        var selection = DriverModelSelection()
        selection.select(library.drivers[0].id, in: library.drivers)
        selection.draft?.name = ""
        selection.apply(to: library)
        #expect(selection.validationError != nil)
        #expect(library.drivers[0].name == "First driver")
        selection.draft?.name = "Renamed driver"
        selection.apply(to: library)
        #expect(selection.validationError == nil)
        #expect(library.drivers[0].name == "Renamed driver")
    }

    @Test func deleteSelectsTheFirstDriverThatRemains() throws {
        let library = try libraryWithTwoDrivers()
        let second = library.drivers[1]
        var selection = DriverModelSelection()
        selection.select(library.drivers[0].id, in: library.drivers)
        selection.deleteSelected(from: library)
        #expect(library.drivers == [second])
        #expect(selection.selectedID == second.id)
        #expect(selection.draft == second)
    }

    @Test func aChangedLibraryStartsTheDraftOver() throws {
        let library = try libraryWithTwoDrivers()
        var selection = DriverModelSelection()
        selection.select(library.drivers[0].id, in: library.drivers)
        selection.draft?.notes = "Unsaved"
        selection.refresh(from: library.drivers)
        #expect(selection.draft?.notes == "")
        library.removeDriver(library.drivers[0].id)
        selection.refresh(from: library.drivers)
        #expect(selection.draft == nil)
    }
}

@MainActor
private func libraryWithTwoDrivers() throws -> DriverLibraryModel {
    try DriverLibraryModel(library: DriverLibrary(drivers: [DriverRecord(name: "First driver"), DriverRecord(name: "Second driver")]))
}
