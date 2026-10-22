import NeXTsoundCore
import SwiftUI

/// The sheet that writes the firmware the app ships with onto the SoundBox and verifies it, opened from the
/// workbench's header and from the front panel's FLASH button.
struct FlashFirmwareSheet: View {
    let connectionState: BoardConnectionState
    @State private var model: FlashFirmwareSheetModel
    @Environment(\.dismiss) private var dismiss

    init(connectionState: BoardConnectionState) {
        self.connectionState = connectionState
        let serial: String? = if case let .verified(capabilities) = connectionState {
            capabilities.serial
        } else {
            nil
        }
        _model = State(initialValue: FlashFirmwareSheetModel(target: FlashTarget(applicationSerial: serial)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flash firmware")
                .font(.headline)
            if model.target.applicationSerial == nil {
                Text("Put the SoundBox into BOOTSEL mode before continuing: hold its BOOTSEL button while connecting the USB cable.")
                    .foregroundStyle(.secondary)
            }
            FlashOutcomeView(outcome: model.outcome)
            if model.outcome == .succeeded {
                RestartStatusView(connectionState: connectionState)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                Button("Flash") { model.flash() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isRunning || model.outcome == .succeeded)
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
                Text(phase.statusText.prefix(1).capitalized + phase.statusText.dropFirst() + "…")
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

/// Picotool only ever talks to a device in BOOTSEL mode, so it cannot confirm the board came back
/// up running the newly flashed firmware; `BoardMonitor`'s own HID discovery, already watching for
/// exactly that reconnect, is the actual source for this.
private struct RestartStatusView: View {
    let connectionState: BoardConnectionState

    var body: some View {
        switch connectionState {
        case let .verified(capabilities):
            Label(
                String(localized: "Board reconnected, running firmware \(capabilities.firmwareVersion)."),
                systemImage: "checkmark.circle"
            )
            .foregroundStyle(.green)
        case .mismatched:
            Label("The board reconnected but did not verify; check it manually.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .disconnected, .detected:
            Label {
                Text("Waiting for the board to reconnect…")
            } icon: {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}
