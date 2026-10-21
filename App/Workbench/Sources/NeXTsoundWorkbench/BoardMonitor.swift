import Foundation
import NeXTsoundCore
import Observation

/// A read-only connection state. No case here ever applies settings or persists to a board;
/// `BoardMonitor.apply(_:)`, `persist()` and `setDeviceName(_:)` are the explicit writes that do.
public enum BoardConnectionState: Equatable, Sendable {
    case disconnected
    case detected
    case verified(DeviceCapabilities)
    case mismatched(String)
}

/// Whether a connected board starts with the settings it plays after its next power-up.
///
/// The firmware advances its active generation with every applied snapshot and records the
/// generation it persisted, and every reply carries the active one. The two agree exactly when
/// the board plays the settings it saved.
public enum BoardStorageState: Equatable, Sendable {
    /// Not read yet, or no board is verified.
    case unknown
    /// The board plays the settings it starts with.
    case saved
    /// The board plays settings it has not saved, so a power cycle returns to other ones.
    case unsaved
    /// The board has no usable storage and cannot save settings.
    case unavailable

    /// Reads the state from a status reply.
    /// - Parameters:
    ///   - activeGeneration: The generation the status reply's header carries.
    ///   - status: The decoded status payload with the persisted generation and storage availability.
    public init(activeGeneration: UInt32, status: DeviceRuntimeStatus) {
        if !status.storageIsAvailable {
            self = .unavailable
        } else {
            self = status.persistedGeneration == activeGeneration ? .saved : .unsaved
        }
    }
}

public struct BoardIdentitySnapshot: Equatable, Sendable {
    public var vendorID: Int
    public var productID: Int
    public var enumeratedSerial: String?

    public init(vendorID: Int, productID: Int, enumeratedSerial: String? = nil) {
        self.vendorID = vendorID
        self.productID = productID
        self.enumeratedSerial = enumeratedSerial
    }
}

public protocol BoardTransport: Sendable {
    /// Sends the non-mutating capabilities request and returns its validated reply. Never applies, persists, or resets.
    func requestCapabilities() async throws -> DeviceCapabilities
    /// Writes a new persisted device name to the board. The new name is visible to macOS
    /// only after the board next resets or is replugged.
    func setDeviceName(_ name: String) async throws
    /// Applies a DSP snapshot to the audio owner for the next block. Never persists to flash;
    /// `persistState()` does that.
    func applyState(_ snapshot: DeviceSnapshot) async throws
    /// Writes the snapshot the board plays to its flash, so the board starts with it after the next
    /// power-up. Returns once the flash write completed.
    func persistState() async throws
    /// Sends the non-mutating runtime-status request and returns its validated reply. Never applies, persists, or resets.
    func requestRuntimeStatus() async throws -> DeviceRuntimeStatus
    /// Sends the non-mutating runtime-status request and reports whether the board plays the settings it saved.
    func requestStorageState() async throws -> BoardStorageState
}

public protocol BoardDiscovery: Sendable {
    func start(
        onConnect: @escaping @Sendable (BoardIdentitySnapshot, any BoardTransport) -> Void,
        onDisconnect: @escaping @Sendable () -> Void
    )
    func stop()
}

@MainActor
@Observable
public final class BoardMonitor {
    public private(set) var state: BoardConnectionState = .disconnected
    public private(set) var storage: BoardStorageState = .unknown

    @ObservationIgnored private let isEnabled: Bool
    @ObservationIgnored private let discovery: any BoardDiscovery
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var queryTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var transport: (any BoardTransport)?

    public init(isEnabled: Bool = true, discovery: (any BoardDiscovery)? = nil) {
        self.isEnabled = isEnabled
        self.discovery = discovery ?? IOHIDBoardDiscovery()
    }
}

public extension BoardMonitor {
    func start() {
        guard
            isEnabled,
            !hasStarted
        else {
            return
        }
        hasStarted = true
        discovery.start(
            onConnect: { [weak self] identity, transport in
                Task { @MainActor in self?.connected(identity, transport) }
            },
            onDisconnect: { [weak self] in
                Task { @MainActor in self?.disconnected() }
            }
        )
    }

    func stop() {
        guard hasStarted else {
            return
        }
        hasStarted = false
        discovery.stop()
        disconnected()
    }

    /// Renames the connected board and refreshes the displayed capabilities to reflect it.
    /// The new name becomes visible to macOS itself only after the board resets or is replugged.
    /// The firmware stores the settings the board plays together with the name, so the storage
    /// state is read again as well.
    func setDeviceName(_ name: String) async throws {
        guard let transport else {
            throw BoardTransportError.notConnected
        }
        let current = generation
        try await transport.setDeviceName(name)
        guard generation == current else {
            return
        }
        let capabilities = try await transport.requestCapabilities()
        let storage = await Self.readStorage(from: transport)
        guard generation == current else {
            return
        }
        state = .verified(capabilities)
        self.storage = storage
    }

    /// Applies a DSP snapshot to the connected board's audio owner for the next block.
    /// Never persists to flash; a reconnect or power cycle reverts to the last persisted state.
    func apply(_ snapshot: DeviceSnapshot) async throws {
        guard let transport else {
            throw BoardTransportError.notConnected
        }
        let current = generation
        try await transport.applyState(snapshot)
        // An applied snapshot advances the firmware's active generation past the one it saved.
        if generation == current, storage == .saved {
            storage = .unsaved
        }
    }

    /// Saves the settings the connected board plays to its flash, so it starts with them after the
    /// next power-up, and reads the storage state again once the flash write completed.
    func persist() async throws {
        guard let transport else {
            throw BoardTransportError.notConnected
        }
        let current = generation
        try await transport.persistState()
        let storage = await Self.readStorage(from: transport)
        guard generation == current else {
            return
        }
        self.storage = storage
    }
}

private extension BoardMonitor {
    func connected(_ identity: BoardIdentitySnapshot, _ transport: any BoardTransport) {
        generation += 1
        let current = generation
        state = .detected
        self.transport = transport
        queryTask?.cancel()
        queryTask = Task { [weak self] in
            do {
                let capabilities = try await transport.requestCapabilities()
                guard
                    let self,
                    generation == current
                else {
                    return
                }
                let enumeratedSerial = identity.enumeratedSerial
                if let enumeratedSerial, !enumeratedSerial.isEmpty, enumeratedSerial != capabilities.serial {
                    state = .mismatched(String(localized: "The reported serial does not match the enumerated device."))
                    return
                }
                let storage = await Self.readStorage(from: transport)
                guard generation == current else {
                    return
                }
                self.storage = storage
                state = .verified(capabilities)
            } catch {
                guard
                    let self,
                    generation == current
                else {
                    return
                }
                state = .mismatched(error.localizedDescription)
            }
        }
    }

    func disconnected() {
        generation += 1
        queryTask?.cancel()
        queryTask = nil
        transport = nil
        state = .disconnected
        storage = .unknown
    }

    /// A board whose storage state cannot be read still verifies; its status line then stays empty.
    static func readStorage(from transport: any BoardTransport) async -> BoardStorageState {
        await (try? transport.requestStorageState()) ?? .unknown
    }
}
