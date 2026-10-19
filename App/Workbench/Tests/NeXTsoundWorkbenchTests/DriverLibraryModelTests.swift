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
        #expect(model.drivers.count == 2)
    }

    @Test func aFailedLoadSurfacesAnErrorButStaysEditable() async {
        let storage = FakeDriverLibraryStorage(loadResult: .failure(FakeStorageError.simulatedFailure))
        let model = DriverLibraryModel(storage: storage)
        await model.start()
        #expect(model.errorMessage != nil)
        #expect(model.isReady)
        model.addDriver()
        #expect(model.drivers.count == 2)
    }

    @Test func addingADriverPersistsIt() async throws {
        let storage = FakeDriverLibraryStorage(loadResult: .value(nil))
        let model = DriverLibraryModel(storage: storage)
        await model.start()
        model.addDriver()
        #expect(model.drivers.count == 2)
        try await Task.sleep(for: .milliseconds(20))
        #expect(storage.savedLibraries.last?.drivers.count == 2)
    }

    @Test func updatingAnUnknownDriverSurfacesAnError() {
        let model = DriverLibraryModel()
        model.updateDriver(DriverRecord(name: "Unknown"))
        #expect(model.errorMessage != nil)
    }

    @Test func removingTheLastDriverSurfacesAnErrorAndKeepsIt() {
        let model = DriverLibraryModel()
        let onlyID = model.drivers[0].id
        model.removeDriver(onlyID)
        #expect(model.errorMessage != nil)
        #expect(model.drivers.count == 1)
    }

    @Test func removingADriverLeavesTheRest() {
        let model = DriverLibraryModel()
        model.addDriver()
        let firstID = model.drivers[0].id
        model.removeDriver(firstID)
        #expect(model.drivers.count == 1)
        #expect(model.drivers.first?.id != firstID)
    }

    @Test func mutatingTheDriverLibraryNeverWritesToAConnectedBoard() async throws {
        let setDeviceNameCalls = CallCounter()
        let discovery = FakeBoardDiscovery()
        let boards = BoardMonitor(discovery: discovery)
        boards.start()
        discovery.simulateConnect(
            BoardIdentitySnapshot(vendorID: 0x1234, productID: 0x5678),
            transport: FakeBoardTransport(behavior: .success(fixtureCapabilities()), setDeviceNameCalls: setDeviceNameCalls)
        )
        try await Task.sleep(for: .milliseconds(20))
        #expect(boards.state == .verified(fixtureCapabilities()))

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
