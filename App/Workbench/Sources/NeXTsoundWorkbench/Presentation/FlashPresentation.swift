import Foundation

extension FlashPhase {
    /// The phase as the flash sheet titles it while it runs: its status text with a capital first letter and an
    /// ellipsis.
    var runningTitle: String {
        statusText.prefix(1).capitalized + statusText.dropFirst() + "…"
    }
}

/// What the flash sheet shows of the board's restart after a successful flash.
///
/// Picotool only ever talks to a device in BOOTSEL mode, so it cannot confirm that the board came back up running the
/// newly flashed firmware. `BoardMonitor`'s own HID discovery, already watching for exactly that reconnect, is the
/// source for this.
enum FlashRestartStatus: Equatable {
    /// The board is back and verified, running `firmwareVersion`.
    case reconnected(firmwareVersion: String)
    /// The board came back but did not verify.
    case unverified
    /// The board has not come back yet.
    case waiting

    init(connectionState: BoardConnectionState) {
        switch connectionState {
        case let .verified(capabilities): self = .reconnected(firmwareVersion: capabilities.firmwareVersion)
        case .mismatched: self = .unverified
        case .disconnected, .detected: self = .waiting
        }
    }
}
