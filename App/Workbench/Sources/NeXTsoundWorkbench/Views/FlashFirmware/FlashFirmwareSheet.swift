import NeXTsoundCore
import SwiftUI

/// The sheet that writes the firmware the app ships with onto the SoundBox and verifies it, opened from the front
/// panel's FLASH button.
struct FlashFirmwareSheet: View {
    let connectionState: BoardConnectionState
    @State private var model: FlashFirmwareSheetModel
    @Environment(\.dismiss) private var dismiss

    init(connectionState: BoardConnectionState) {
        self.connectionState = connectionState
        let target = FlashTarget(applicationSerial: connectionState.verifiedCapabilities?.serial)
        _model = State(initialValue: FlashFirmwareSheetModel(target: target))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flash firmware")
                .font(.headline)
            if model.needsBootselByHand {
                Text("Put the SoundBox into BOOTSEL mode before continuing: hold its BOOTSEL button while connecting the USB cable.")
                    .foregroundStyle(.secondary)
            }
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

/// The board's restart after a successful flash, as `FlashRestartStatus` reads it from the board monitor.
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
