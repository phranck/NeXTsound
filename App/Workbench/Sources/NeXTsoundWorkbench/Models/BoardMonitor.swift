import Foundation
import NeXTsoundCore
import Observation

/// A read-only connection state. No case here ever applies settings or persists to a board;
/// `BoardMonitor.apply(_:)`, `persist()`, `setDeviceName(_:)` and `writeMetadata(_:)` are the explicit writes that do.
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

@MainActor
@Observable
public final class BoardMonitor {
    public private(set) var state: BoardConnectionState = .disconnected
    public private(set) var storage: BoardStorageState = .unknown
    /// The verified board's live values, read about once every `statusInterval`. Nil while no board is verified.
    public private(set) var runtime: DeviceRuntimeStatus?
    /// The verified board's owner metadata, read when it connects and after every metadata write. Nil while no board
    /// is verified, and for a board whose capabilities report no metadata feature.
    public private(set) var metadata: OwnerMetadata?
    /// Called with the board's chip serial whenever the monitor reads its metadata, so the serial-number register can
    /// take over a number the board already carries.
    @ObservationIgnored public var onMetadataRead: (@MainActor (String, OwnerMetadata) -> Void)?
    /// Called when a newly connected board finishes verification, not when an already verified board refreshes its
    /// capabilities. The app uses this for work that belongs to the first verified board of a session.
    @ObservationIgnored public var onVerified: (@MainActor (DeviceCapabilities) -> Void)?

    @ObservationIgnored private let isEnabled: Bool
    @ObservationIgnored private let discovery: any BoardDiscovery
    @ObservationIgnored private let statusInterval: Duration
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var queryTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var transport: (any BoardTransport)?
    @ObservationIgnored private var writesInFlight = 0
    @ObservationIgnored private var writeCount = 0

    /// - Parameters:
    ///   - isEnabled: Whether `start()` looks for boards at all.
    ///   - discovery: How boards are found, the system's HID discovery unless a test passes its own.
    ///   - statusInterval: How long the monitor waits between two reads of a verified board's live values.
    public init(isEnabled: Bool = true, discovery: (any BoardDiscovery)? = nil, statusInterval: Duration = .seconds(1)) {
        self.isEnabled = isEnabled
        self.discovery = discovery ?? IOHIDBoardDiscovery()
        self.statusInterval = statusInterval
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
        beginWrite()
        defer { endWrite() }
        try await transport.setDeviceName(name)
        guard generation == current else {
            return
        }
        let capabilities = try await transport.requestCapabilities()
        let status = await Self.readStatus(from: transport)
        guard generation == current else {
            return
        }
        state = .verified(capabilities)
        show(status)
    }

    /// Writes new owner metadata to the connected board, which saves it to flash, and reads it back. The firmware
    /// saves the settings the board plays with it, so the storage state is read again as well.
    func writeMetadata(_ metadata: OwnerMetadata) async throws {
        guard let transport else {
            throw BoardTransportError.notConnected
        }
        let current = generation
        beginWrite()
        defer { endWrite() }
        try await transport.writeMetadata(metadata)
        let written = try await transport.requestMetadata()
        let status = await Self.readStatus(from: transport)
        guard generation == current else {
            return
        }
        self.metadata = written
        show(status)
    }

    /// Applies a DSP snapshot to the connected board's audio owner for the next block.
    /// Never persists to flash; a reconnect or power cycle reverts to the last persisted state.
    func apply(_ snapshot: DeviceSnapshot) async throws {
        guard let transport else {
            throw BoardTransportError.notConnected
        }
        // A board refuses a snapshot beyond the ranges its capabilities report, and older firmware reports narrower ones,
        // such as Master Volume up to 0 dB. A profile beyond them plays at the nearest value the board takes.
        var limited = snapshot
        if let capabilities = state.verifiedCapabilities {
            limited.settings = snapshot.settings.limited(to: capabilities.parameterRanges)
        }
        let current = generation
        beginWrite()
        defer { endWrite() }
        try await transport.applyState(limited)
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
        beginWrite()
        defer { endWrite() }
        try await transport.persistState()
        let status = await Self.readStatus(from: transport)
        guard generation == current else {
            return
        }
        show(status)
    }
}

private extension BoardMonitor {
    func connected(_ identity: BoardIdentitySnapshot, _ transport: any BoardTransport) {
        generation += 1
        let current = generation
        state = .detected
        self.transport = transport
        queryTask?.cancel()
        statusTask?.cancel()
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
                let status = await Self.readStatus(from: transport)
                let metadata = await Self.readMetadata(from: transport, capabilities: capabilities)
                guard generation == current else {
                    return
                }
                show(status)
                self.metadata = metadata
                state = .verified(capabilities)
                onVerified?(capabilities)
                if let metadata {
                    onMetadataRead?(capabilities.serial, metadata)
                }
                readStatusContinually(from: transport, generation: current)
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
        statusTask?.cancel()
        statusTask = nil
        transport = nil
        state = .disconnected
        storage = .unknown
        runtime = nil
        metadata = nil
    }

    /// Reads the verified board's live values every `statusInterval` until it disconnects. A read waits while a
    /// write is on the wire, and a reading that a write overtook is dropped, so the storage state never runs behind
    /// an apply.
    func readStatusContinually(from transport: any BoardTransport, generation current: Int) {
        statusTask = Task { [weak self, statusInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: statusInterval)
                guard
                    let self,
                    generation == current
                else {
                    return
                }
                guard writesInFlight == 0 else {
                    continue
                }
                let writes = writeCount
                guard let reading = try? await transport.requestStatus() else {
                    continue
                }
                if generation == current, writeCount == writes, writesInFlight == 0 {
                    show(reading)
                }
            }
        }
    }

    func beginWrite() {
        writesInFlight += 1
        writeCount += 1
    }

    func endWrite() {
        writesInFlight -= 1
    }

    /// Shows what a status request read. A failed read leaves the storage state unknown and keeps the last live
    /// values.
    func show(_ reading: BoardStatusReading?) {
        storage = reading?.storage ?? .unknown
        if let reading {
            runtime = reading.runtime
        }
    }

    /// A board whose status cannot be read still verifies; its status lines then stay empty.
    static func readStatus(from transport: any BoardTransport) async -> BoardStatusReading? {
        try? await transport.requestStatus()
    }

    /// A board without the metadata feature, or whose metadata cannot be read, still verifies; its metadata lines
    /// then stay away.
    static func readMetadata(from transport: any BoardTransport, capabilities: DeviceCapabilities) async -> OwnerMetadata? {
        guard capabilities.supportsMetadata else {
            return nil
        }
        return try? await transport.requestMetadata()
    }
}
