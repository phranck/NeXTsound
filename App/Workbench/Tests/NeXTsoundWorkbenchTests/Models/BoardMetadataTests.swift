import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct BoardMetadataTests {
    @Test func aBoardWithTheMetadataFeatureHasItsMetadataReadWhenItConnects() async throws {
        let transport = FakeBoardTransport(behavior: .success(metadataCapabilities()))
        transport.metadata.value = OwnerMetadata(serialNumber: 5, owner: "Frank")
        let monitor = try await verifiedMonitor(transport)
        #expect(monitor.metadata == OwnerMetadata(serialNumber: 5, owner: "Frank"))
    }

    @Test func aBoardWithoutTheFeatureHasNoMetadata() async throws {
        let transport = FakeBoardTransport(behavior: .success(fixtureCapabilities()))
        transport.metadata.value = OwnerMetadata(serialNumber: 5)
        let monitor = try await verifiedMonitor(transport)
        #expect(monitor.metadata == nil)
    }

    @Test func writingMetadataReadsItBackFromTheBoard() async throws {
        let transport = FakeBoardTransport(behavior: .success(metadataCapabilities()))
        let monitor = try await verifiedMonitor(transport)
        let written = OwnerMetadata(date: CalendarDay(year: 2026, month: 10, day: 24), serialNumber: 1, owner: "Frank")
        try await monitor.writeMetadata(written)
        #expect(monitor.metadata == written && transport.metadata.writes == 1)
        monitor.stop()
        #expect(monitor.metadata == nil)
    }

    @Test func editingTheBoardWritesWhatChangedAndRegistersTheNumber() async throws {
        let storage = FakeSerialNumberStorage()
        let renames = CallCounter()
        var transport = FakeBoardTransport(behavior: .success(metadataCapabilities()))
        transport.setDeviceNameCalls = renames
        let model = try await connectedModel(transport, storage: storage)
        await model.editBoard(name: "", metadata: OwnerMetadata(serialNumber: 1, owner: "Frank"))
        #expect(renames.total == 0 && transport.metadata.writes == 1)
        #expect(model.serialNumbers.numbers == [chip: 1])
        #expect(storage.savedRegisters.last == model.serialNumbers)
        await model.editBoard(name: "Bedroom SoundBox", metadata: OwnerMetadata(serialNumber: 1, owner: "Frank"))
        #expect(renames.total == 1 && transport.metadata.writes == 1)
        await model.editBoard(name: "Bedroom SoundBox", metadata: OwnerMetadata(owner: "Frank"))
        #expect(model.serialNumbers.numbers.isEmpty)
    }

    @Test func theNumberAConnectedBoardCarriesIsTakenIntoTheRegister() async throws {
        let storage = FakeSerialNumberStorage(loadResult: .success(SerialNumberRegister(numbers: ["OTHER": 1])))
        let transport = FakeBoardTransport(behavior: .success(metadataCapabilities()))
        transport.metadata.value = OwnerMetadata(serialNumber: 4)
        let model = try await connectedModel(transport, storage: storage)
        #expect(await waitUntil { storage.savedRegisters.last?.numbers == ["OTHER": 1, chip: 4] })
        #expect(model.serialNumbers.proposal(for: "NEXT") == 2)
    }

    @Test func anUnreadableRegisterKeepsTheFormFromNumberingABoard() async throws {
        let storage = FakeSerialNumberStorage(loadResult: .failure(.simulatedFailure))
        let transport = FakeBoardTransport(behavior: .success(metadataCapabilities()))
        transport.metadata.value = OwnerMetadata(serialNumber: 4)
        let model = try await connectedModel(transport, storage: storage)
        #expect(!model.serialNumbersAreAvailable && model.errorMessage != nil)
        #expect(model.serialNumbers.numbers.isEmpty && storage.savedRegisters.isEmpty)
    }
}

private extension BoardMetadataTests {
    var chip: String {
        fixtureCapabilities().serial
    }

    /// A board with verified flash, persistence and the metadata feature, whose wire flags are 1, 2 and 8.
    func metadataCapabilities() -> DeviceCapabilities {
        var capabilities = fixtureCapabilities()
        capabilities.flashSizeBytes = 4 * 1_048_576
        capabilities.featureFlags = 1 | 2 | 8
        #expect(capabilities.supportsPersistence && capabilities.flashIsVerified && capabilities.supportsMetadata)
        return capabilities
    }

    /// A started model whose monitor verified the fake board and read its metadata.
    func connectedModel(_ transport: FakeBoardTransport, storage: FakeSerialNumberStorage) async throws -> WorkbenchModel {
        let discovery = FakeBoardDiscovery()
        let monitor = BoardMonitor(discovery: discovery)
        let model = WorkbenchModel(boards: monitor, serialNumberStorage: storage)
        await model.start()
        discovery.simulateConnect(BoardIdentitySnapshot(vendorID: 1, productID: 2, enumeratedSerial: chip), transport: transport)
        guard await waitUntil({ monitor.metadata != nil }) else {
            throw BoardTransportError.timeout
        }
        return model
    }
}
