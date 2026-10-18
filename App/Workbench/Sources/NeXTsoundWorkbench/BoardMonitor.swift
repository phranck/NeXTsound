import Foundation
import NeXTsoundCore
import Observation

/// A read-only connection state. No case here ever applies settings or persists to a board.
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
}

private extension BoardMonitor {
    func connected(_ identity: BoardIdentitySnapshot, _ transport: any BoardTransport) {
        generation += 1
        let current = generation
        state = .detected
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
                    state = .mismatched("The reported serial does not match the enumerated device.")
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
        state = .disconnected
    }
}
