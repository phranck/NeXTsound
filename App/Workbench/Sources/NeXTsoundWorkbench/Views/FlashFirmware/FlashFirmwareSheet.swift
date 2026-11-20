import NeXTsoundCore
import SwiftUI

/// The sheet that writes the firmware the app ships with onto the SoundBox and verifies it, opened from the front
/// panel's FLASH button.
struct FlashFirmwareSheet: View {
    let connectionState: BoardConnectionState
    @State private var model: FlashFirmwareSheetModel
    @Environment(\.dismiss) private var dismiss

    init(connectionState: BoardConnectionState, releaseService: (any FirmwareReleaseService)? = nil) {
        self.connectionState = connectionState
        let target = FlashTarget(
            applicationSerial: connectionState.verifiedCapabilities?.serial,
            applicationVersion: connectionState.verifiedCapabilities?.firmwareVersion
        )
        _model = State(initialValue: FlashFirmwareSheetModel(target: target, releaseService: releaseService))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flash firmware")
                .font(.headline)
            if model.needsBootselByHand {
                Text("Put the SoundBox into BOOTSEL mode before continuing: hold its BOOTSEL button while connecting the USB cable.")
                    .foregroundStyle(.secondary)
            }
            FirmwareUpdateView(
                state: model.updateState,
                onCheck: model.checkForUpdates,
                onInstall: model.installUpdate,
                onDecline: model.declineUpdate
            )
            FlashOutcomeView(outcome: model.outcome)
            if model.showsRestartStatus {
                RestartStatusView(status: FlashRestartStatus(connectionState: connectionState))
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                Button("Flash") { model.flash() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canFlash)
            }
        }
        .padding(16)
        .frame(width: 420)
        .task { await model.checkForUpdates() }
    }
}

private struct FirmwareUpdateView: View {
    let state: FlashFirmwareSheetModel.UpdateState
    let onCheck: () async -> Void
    let onInstall: () -> Void
    let onDecline: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .checking:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Checking for firmware updates…")
                    .foregroundStyle(.secondary)
            }
        case let .available(release):
            VStack(alignment: .leading, spacing: 8) {
                Text("Firmware \(release.version.description) is available. Install it?")
                HStack {
                    Button("Update", action: onInstall)
                        .keyboardShortcut(.defaultAction)
                    Button("Not now", role: .cancel, action: onDecline)
                }
            }
        case .upToDate:
            Text("Firmware is up to date.")
                .foregroundStyle(.secondary)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("Try again") {
                    Task { await onCheck() }
                }
            }
        }
    }
}

private struct FlashOutcomeView: View {
    let outcome: FlashFirmwareSheetModel.Outcome

    var body: some View {
        switch outcome {
        case .idle:
            EmptyView()
        case let .running(phase):
            VStack(alignment: .leading, spacing: 6) {
                Text(phase.runningTitle)
                ProgressView(value: phase.progress, total: 1)
                    .progressViewStyle(.linear)
            }
        case .succeeded:
            Label("Firmware written and verified.", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}

// The board's restart after a successful flash, as `FlashRestartStatus` reads it from the board monitor.
#Preview("Update available") {
    FirmwareUpdateView(
        state: .available(FirmwareRelease(
            version: FirmwareVersion(major: 99, minor: 0, patch: 1),
            assetURL: URL(string: "https://github.com/phranck/NeXTsound/releases/download/firmware-v99.0.1/nxs_firmware.uf2")!
        )),
        onCheck: {},
        onInstall: {},
        onDecline: {}
    )
    .padding(16)
}

private struct RestartStatusView: View {
    let status: FlashRestartStatus

    var body: some View {
        switch status {
        case let .reconnected(firmwareVersion):
            Label(String(localized: "Board reconnected, running firmware \(firmwareVersion)."), systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .unverified:
            Label("The board reconnected but did not verify; check it manually.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .waiting:
            Label {
                Text("Waiting for the board to reconnect…")
            } icon: {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}
