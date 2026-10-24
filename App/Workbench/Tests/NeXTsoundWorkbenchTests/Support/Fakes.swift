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

final class FakeDriverLibraryStorage: DriverLibraryStorage, @unchecked Sendable {
    enum LoadResult {
        case value(DriverLibrary?)
        case failure(any Error)
    }

    var loadResult: LoadResult
    private(set) var savedLibraries: [DriverLibrary] = []
    var saveError: (any Error)?

    init(loadResult: LoadResult = .value(nil)) {
        self.loadResult = loadResult
    }

    func load() async throws -> DriverLibrary? {
        switch loadResult {
        case let .value(library): return library
        case let .failure(error): throw error
        }
    }

    func save(_ library: DriverLibrary) async throws {
        if let saveError {
            throw saveError
        }
        savedLibraries.append(library)
    }
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

final class CallCounter: @unchecked Sendable {
    private(set) var total = 0
    func increment() {
        total += 1
    }
}

final class SnapshotRecorder: @unchecked Sendable {
    private(set) var snapshots: [DeviceSnapshot] = []
    func record(_ snapshot: DeviceSnapshot) {
        snapshots.append(snapshot)
    }
}

/// Records every write a fake board receives, in order, so a test can tell an apply from a persist.
final class BoardWriteRecorder: @unchecked Sendable {
    enum Write: Equatable {
        case apply(DeviceSnapshot)
        case persist
    }

    private(set) var writes: [Write] = []

    func record(_ write: Write) {
        writes.append(write)
    }
}

/// The fake board's storage state, shared between the copies of one `FakeBoardTransport` value.
final class FakeBoardStorage: @unchecked Sendable {
    var state: BoardStorageState

    init(_ state: BoardStorageState = .saved) {
        self.state = state
    }
}

final class FlashPhaseRecorder: @unchecked Sendable {
    private(set) var phases: [FlashPhase] = []
    func record(_ phase: FlashPhase) {
        phases.append(phase)
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
    var setDeviceNameCalls: CallCounter?
    var applyError: BoardTransportError?
    var applyStateCalls: CallCounter?
    var appliedSnapshots: SnapshotRecorder?
    var applyDelay: Duration?
    /// Holds every apply on the wire until the stream finishes, so a test decides when the write ends.
    var applyRelease: AsyncStream<Void>?
    var persistError: BoardTransportError?
    var writes: BoardWriteRecorder?
    var storage = FakeBoardStorage()
    /// The live values every status request reports.
    var runtime = DeviceRuntimeStatus()
    var statusCalls: CallCounter?
    /// The owner metadata every metadata request reports.
    var metadata = OwnerMetadata()

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
        setDeviceNameCalls?.increment()
        if let renameError {
            throw renameError
        }
    }

    func requestStatus() async throws -> BoardStatusReading {
        statusCalls?.increment()
        return BoardStatusReading(runtime: runtime, storage: storage.state)
    }

    func applyState(_ snapshot: DeviceSnapshot) async throws {
        applyStateCalls?.increment()
        appliedSnapshots?.record(snapshot)
        if let applyDelay {
            try await Task.sleep(for: applyDelay)
        }
        if let applyRelease {
            for await _ in applyRelease {}
        }
        if let applyError {
            throw applyError
        }
        writes?.record(.apply(snapshot))
        // Like the firmware, an applied snapshot moves the board past the settings it saved.
        if storage.state == .saved {
            storage.state = .unsaved
        }
    }

    func persistState() async throws {
        if let persistError {
            throw persistError
        }
        writes?.record(.persist)
        storage.state = .saved
    }

    func requestMetadata() async throws -> OwnerMetadata {
        metadata
    }

    func writeMetadata(_: OwnerMetadata) async throws {}
}

func fixtureCapabilities(serial: String = "D4CDD489AFE28CC5") -> DeviceCapabilities {
    DeviceCapabilities(serial: serial, firmwareVersion: "1.0.0")
}

/// Waits until a condition holds, checking it every five milliseconds, and tells whether it held before the timeout.
///
/// The work a test waits for runs on the main actor, so a fixed sleep runs out whenever another test keeps the main
/// actor busy for longer than the sleep lasts. The timeout is long for the same reason: the render tests hold the main
/// actor for seconds on a CI runner, and every caller waits for a state it expects, so the timeout only bounds a wait
/// that fails.
@MainActor
@discardableResult
func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Starts a monitor, connects the fake board through the discovery, and returns once the monitor
/// verified it. Throws a timeout when verification takes longer than `waitUntil(timeout:_:)` waits.
@MainActor
func verifiedMonitor(
    _ transport: FakeBoardTransport,
    discovery: FakeBoardDiscovery = FakeBoardDiscovery(),
    statusInterval: Duration = .seconds(1)
) async throws -> BoardMonitor {
    let monitor = BoardMonitor(discovery: discovery, statusInterval: statusInterval)
    monitor.start()
    discovery.simulateConnect(
        BoardIdentitySnapshot(vendorID: 1, productID: 2, enumeratedSerial: fixtureCapabilities().serial),
        transport: transport
    )
    let verified = await waitUntil {
        if case .verified = monitor.state {
            true
        } else {
            false
        }
    }
    guard verified else {
        throw BoardTransportError.timeout
    }
    return monitor
}

final class FakePicotoolRunner: PicotoolRunning, @unchecked Sendable {
    private(set) var invocations: [[String]] = []
    var exitCodeByCommand: [String: Int32] = [:]
    var outputByCommand: [String: String] = [:]
    /// How many "info" calls return "not found" before one succeeds; 0 means the first call succeeds.
    var infoAttemptsBeforeSuccess = 0
    private var infoAttempts = 0

    func run(arguments: [String]) async throws -> (exitCode: Int32, output: String) {
        invocations.append(arguments)
        let command = arguments.first ?? ""
        if command == "info" {
            infoAttempts += 1
            if infoAttempts <= infoAttemptsBeforeSuccess {
                return (249, "No accessible RP-series devices in BOOTSEL mode were found.")
            }
            return (0, "")
        }
        return (exitCodeByCommand[command] ?? 0, outputByCommand[command] ?? "")
    }
}
