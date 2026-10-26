import Foundation
import NeXTsoundCore
import Synchronization
@testable import NeXTsoundWorkbench

/// A value a fake changes from the global executor while a test reads it on the main actor.
///
/// A fake's async methods run off the main actor, so an array they append to without a lock can be read half-written,
/// and `Array.last` then traps with "Index out of range". Every read and every change goes through the lock.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    /// The current value, copied out under the lock.
    var value: Value {
        mutex.withLock { $0 }
    }

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    /// Changes the value under the lock and returns what `change` returns.
    @discardableResult
    func mutate<Result: Sendable>(_ change: (inout Value) -> Result) -> Result {
        mutex.withLock { change(&$0) }
    }
}

/// A profile library storage that records every save. A test sets `loadResult` and `saveError` before the model starts,
/// so only the saved libraries, which the model's saves append to off the main actor, need the lock.
final class FakeProfileLibraryStorage: ProfileLibraryStorage, @unchecked Sendable {
    enum LoadResult {
        case value(ProfileLibrary?)
        case failure(any Error)
    }

    var loadResult: LoadResult
    var saveError: (any Error)?
    private let saved = Locked<[ProfileLibrary]>([])

    /// Every library the model saved, oldest first.
    var savedLibraries: [ProfileLibrary] {
        saved.value
    }

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
        saved.mutate { $0.append(library) }
    }
}

enum FakeStorageError: Error, Equatable {
    case simulatedFailure
}

/// A driver library storage that records every save. A test sets `loadResult` and `saveError` before the model starts,
/// so only the saved libraries, which the model's saves append to off the main actor, need the lock.
final class FakeDriverLibraryStorage: DriverLibraryStorage, @unchecked Sendable {
    enum LoadResult {
        case value(DriverLibrary?)
        case failure(any Error)
    }

    var loadResult: LoadResult
    var saveError: (any Error)?
    private let saved = Locked<[DriverLibrary]>([])

    /// Every library the model saved, oldest first.
    var savedLibraries: [DriverLibrary] {
        saved.value
    }

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
        saved.mutate { $0.append(library) }
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

/// Counts the calls a fake board receives, which its async methods make off the main actor.
final class CallCounter: Sendable {
    private let count = Locked(0)

    var total: Int {
        count.value
    }

    func increment() {
        count.mutate { $0 += 1 }
    }
}

/// Records every snapshot a fake board receives, in order.
final class SnapshotRecorder: Sendable {
    private let recorded = Locked<[DeviceSnapshot]>([])

    var snapshots: [DeviceSnapshot] {
        recorded.value
    }

    func record(_ snapshot: DeviceSnapshot) {
        recorded.mutate { $0.append(snapshot) }
    }
}

/// Records every write a fake board receives, in order, so a test can tell an apply from a persist.
final class BoardWriteRecorder: Sendable {
    enum Write: Equatable, Sendable {
        case apply(DeviceSnapshot)
        case persist
    }

    private let recorded = Locked<[Write]>([])

    var writes: [Write] {
        recorded.value
    }

    func record(_ write: Write) {
        recorded.mutate { $0.append(write) }
    }
}

/// The fake board's storage state, shared between the copies of one `FakeBoardTransport` value.
final class FakeBoardStorage: Sendable {
    private let current: Locked<BoardStorageState>

    var state: BoardStorageState {
        get { current.value }
        set { current.mutate { $0 = newValue } }
    }

    init(_ state: BoardStorageState = .saved) {
        current = Locked(state)
    }
}

/// The fake board's owner metadata, shared between the copies of one `FakeBoardTransport` value.
final class FakeBoardMetadata: Sendable {
    private let current: Locked<OwnerMetadata>
    private let writeCount = Locked(0)

    var value: OwnerMetadata {
        get { current.value }
        set { current.mutate { $0 = newValue } }
    }

    /// How many metadata writes the fake board received.
    var writes: Int {
        writeCount.value
    }

    init(_ value: OwnerMetadata = OwnerMetadata()) {
        current = Locked(value)
    }

    /// Takes `written` as the board's metadata, as a write from the app does, and counts the write.
    func receiveWrite(_ written: OwnerMetadata) {
        current.mutate { $0 = written }
        writeCount.mutate { $0 += 1 }
    }
}

/// A serial number register storage that records every save. A test sets `loadResult` before the model starts, so
/// only the saved registers, which the model's saves append to off the main actor, need the lock.
final class FakeSerialNumberStorage: SerialNumberRegisterStorage, @unchecked Sendable {
    var loadResult: Result<SerialNumberRegister?, FakeStorageError>
    private let saved = Locked<[SerialNumberRegister]>([])

    /// Every register the model saved, oldest first.
    var savedRegisters: [SerialNumberRegister] {
        saved.value
    }

    init(loadResult: Result<SerialNumberRegister?, FakeStorageError> = .success(nil)) {
        self.loadResult = loadResult
    }

    func load() async throws -> SerialNumberRegister? {
        try loadResult.get()
    }

    func save(_ register: SerialNumberRegister) async throws {
        saved.mutate { $0.append(register) }
    }
}

/// Records every phase a flash passes through, in order.
final class FlashPhaseRecorder: Sendable {
    private let recorded = Locked<[FlashPhase]>([])

    var phases: [FlashPhase] {
        recorded.value
    }

    func record(_ phase: FlashPhase) {
        recorded.mutate { $0.append(phase) }
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
    /// The owner metadata the fake board carries, which metadata requests report and metadata writes replace.
    var metadata = FakeBoardMetadata()
    var metadataError: BoardTransportError?

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
        if let metadataError {
            throw metadataError
        }
        return metadata.value
    }

    func writeMetadata(_ written: OwnerMetadata) async throws {
        if let metadataError {
            throw metadataError
        }
        metadata.receiveWrite(written)
    }
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

/// A picotool that answers from tables and records every call. A test sets the tables before the flash starts, so only
/// the calls and the "info" attempts, which the flash makes off the main actor, need the lock.
final class FakePicotoolRunner: PicotoolRunning, @unchecked Sendable {
    var exitCodeByCommand: [String: Int32] = [:]
    var outputByCommand: [String: String] = [:]
    /// How many "info" calls return "not found" before one succeeds; 0 means the first call succeeds.
    var infoAttemptsBeforeSuccess = 0
    private let recorded = Locked<[[String]]>([])
    private let infoAttempts = Locked(0)

    /// The arguments of every call, in order.
    var invocations: [[String]] {
        recorded.value
    }

    func run(arguments: [String]) async throws -> (exitCode: Int32, output: String) {
        recorded.mutate { $0.append(arguments) }
        let command = arguments.first ?? ""
        if command == "info" {
            let attempt = infoAttempts.mutate { attempts -> Int in
                attempts += 1
                return attempts
            }
            if attempt <= infoAttemptsBeforeSuccess {
                return (249, "No accessible RP-series devices in BOOTSEL mode were found.")
            }
            return (0, "")
        }
        return (exitCodeByCommand[command] ?? 0, outputByCommand[command] ?? "")
    }
}
