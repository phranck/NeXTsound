import Foundation
import NeXTsoundCore
import Observation

/// A read-only connection state. No case here ever applies settings or persists to a board;
/// `BoardMonitor.apply(_:)` is the one explicit write that does.
public enum BoardConnectionState: Equatable, Sendable {
    case disconnected
    case detected
    case verified(DeviceCapabilities)
    case mismatched(String)
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
    /// see `WireOperation.persistState` for that, which this transport does not yet implement.
    func applyState(_ snapshot: DeviceSnapshot) async throws
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
        guard generation == current else {
            return
        }
        state = .verified(capabilities)
    }

    /// Applies a DSP snapshot to the connected board's audio owner for the next block.
    /// Never persists to flash; a reconnect or power cycle reverts to the last persisted state.
    func apply(_ snapshot: DeviceSnapshot) async throws {
        guard let transport else {
            throw BoardTransportError.notConnected
        }
        try await transport.applyState(snapshot)
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
                } else {
                    state = .verified(capabilities)
                }
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
    }
}
