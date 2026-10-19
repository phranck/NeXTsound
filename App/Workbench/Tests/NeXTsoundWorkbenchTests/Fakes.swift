import Foundation
import NeXTsoundCore
@testable import NeXTsoundWorkbench

final class FakeProfileLibraryStorage: ProfileLibraryStorage, @unchecked Sendable {
    enum LoadResult {
        case value(ProfileLibrary?)
        case failure(any Error)
    }

    var loadResult: LoadResult
    private(set) var savedLibraries: [ProfileLibrary] = []
    var saveError: (any Error)?

    init(loadResult: LoadResult = .value(nil)) {
        self.loadResult = loadResult
    }

    func load() async throws -> ProfileLibrary? {
        switch loadResult {
        case let .value(library): return library
        case let .failure(error): throw error
        }
    }

    func save(_ library: ProfileLibrary) async throws {
        if let saveError {
            throw saveError
        }
        savedLibraries.append(library)
    }
}

enum FakeStorageError: Error, Equatable {
    case simulatedFailure
}

final class FakeBoardDiscovery: BoardDiscovery, @unchecked Sendable {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onConnect: (@Sendable (BoardIdentitySnapshot, any BoardTransport) -> Void)?
    private var onDisconnect: (@Sendable () -> Void)?

    func start(
        onConnect: @escaping @Sendable (BoardIdentitySnapshot, any BoardTransport) -> Void,
        onDisconnect: @escaping @Sendable () -> Void
    ) {
        startCount += 1
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
    }

    func stop() {
        stopCount += 1
        onConnect = nil
        onDisconnect = nil
    }

    func simulateConnect(_ identity: BoardIdentitySnapshot, transport: any BoardTransport) {
        onConnect?(identity, transport)
    }

    func simulateDisconnect() {
        onDisconnect?()
    }
}

struct FakeBoardTransport: BoardTransport {
    enum Behavior: Sendable {
        case success(DeviceCapabilities)
        case failure(BoardTransportError)
        case delayed(DeviceCapabilities, Duration)
        case hangs
    }

    var behavior: Behavior
    var renameError: BoardTransportError?

    func requestCapabilities() async throws -> DeviceCapabilities {
        switch behavior {
        case let .success(capabilities): return capabilities
        case let .failure(error): throw error
        case let .delayed(capabilities, duration):
            try await Task.sleep(for: duration)
            return capabilities
        case .hangs:
            try await Task.sleep(for: .seconds(3600))
            throw BoardTransportError.timeout
        }
    }

    func setDeviceName(_: String) async throws {
        if let renameError {
            throw renameError
        }
    }
}

func fixtureCapabilities(serial: String = "D4CDD489AFE28CC5") -> DeviceCapabilities {
    DeviceCapabilities(serial: serial, firmwareVersion: "1.0.0")
}
