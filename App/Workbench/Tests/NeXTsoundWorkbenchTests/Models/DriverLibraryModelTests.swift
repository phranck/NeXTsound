import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct DriverLibraryModelTests {
    @Test func startLoadsTheStoredLibrary() async throws {
        var stored = DriverLibrary()
        try stored.insert(DriverRecord(name: "Stored driver"))
        let storage = FakeDriverLibraryStorage(loadResult: .value(stored))
        let model = DriverLibraryModel(storage: storage)
        await model.start()
        #expect(model.drivers.count == DriverLibrary.knownCandidates.count + 1)
    }

    @Test func aFailedLoadSurfacesAnErrorButStaysEditable() async {
        let storage = FakeDriverLibraryStorage(loadResult: .failure(FakeStorageError.simulatedFailure))
        let model = DriverLibraryModel(storage: storage)
        await model.start()
        #expect(model.errorMessage != nil)
        #expect(model.isReady)
        model.addDriver()
        #expect(model.drivers.count == DriverLibrary.knownCandidates.count + 1)
    }

    @Test func addingADriverPersistsIt() async {
        let storage = FakeDriverLibraryStorage(loadResult: .value(nil))
        let model = DriverLibraryModel(storage: storage)
        await model.start()
        model.addDriver()
        #expect(model.drivers.count == DriverLibrary.knownCandidates.count + 1)
        await waitUntil { storage.savedLibraries.last?.drivers.count == DriverLibrary.knownCandidates.count + 1 }
        #expect(storage.savedLibraries.last?.drivers.count == DriverLibrary.knownCandidates.count + 1)
    }

    @Test func updatingAnUnknownDriverSurfacesAnError() {
        let model = DriverLibraryModel()
        model.updateDriver(DriverRecord(name: "Unknown"))
        #expect(model.errorMessage != nil)
    }

    @Test func removingTheLastDriverSurfacesAnErrorAndKeepsIt() throws {
        let library = try DriverLibrary(drivers: [DriverRecord()])
        let model = DriverLibraryModel(library: library)
        let onlyID = model.drivers[0].id
        model.removeDriver(onlyID)
        #expect(model.errorMessage != nil)
        #expect(model.drivers.count == 1)
    }

    @Test func removingADriverLeavesTheRest() throws {
        let library = try DriverLibrary(drivers: [DriverRecord()])
        let model = DriverLibraryModel(library: library)
        model.addDriver()
        let firstID = model.drivers[0].id
        model.removeDriver(firstID)
        #expect(model.drivers.count == 1)
        #expect(model.drivers.first?.id != firstID)
    }

    @Test func mutatingTheDriverLibraryNeverWritesToAConnectedBoard() async throws {
        let setDeviceNameCalls = CallCounter()
        let boards = try await verifiedMonitor(FakeBoardTransport(
            behavior: .success(fixtureCapabilities()),
            setDeviceNameCalls: setDeviceNameCalls
        ))

        let model = DriverLibraryModel()
        model.addDriver()
        var driver = model.drivers[0]
        driver.notes = "Edited"
        model.updateDriver(driver)
        model.removeDriver(model.drivers[1].id)

        #expect(setDeviceNameCalls.total == 0)
        #expect(boards.state == .verified(fixtureCapabilities()))
    }
}
