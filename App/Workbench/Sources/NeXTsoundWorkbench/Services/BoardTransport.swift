import NeXTsoundCore

/// The requests the app sends a connected SoundBox. `USBHostBoardTransport` sends them over USB, and the tests pass a
/// fake.
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
    /// Sends the non-mutating runtime-status request and returns the board's live values together with whether it
    /// plays the settings it saved, both from the one validated reply. Never applies, persists, or resets.
    func requestStatus() async throws -> BoardStatusReading
}

public extension BoardTransport {
    /// The live values of one runtime-status request.
    func requestRuntimeStatus() async throws -> DeviceRuntimeStatus {
        try await requestStatus().runtime
    }

    /// Whether the board plays the settings it saved, from one runtime-status request.
    func requestStorageState() async throws -> BoardStorageState {
        try await requestStatus().storage
    }
}

/// What one runtime-status request reports.
public struct BoardStatusReading: Equatable, Sendable {
    /// The board's live values: streaming, host volume and mute, peaks, xruns and processing time.
    public var runtime: DeviceRuntimeStatus
    /// Whether the board plays the settings it saved.
    public var storage: BoardStorageState

    public init(runtime: DeviceRuntimeStatus, storage: BoardStorageState) {
        self.runtime = runtime
        self.storage = storage
    }
}
