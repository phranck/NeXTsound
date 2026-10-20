import NeXTsoundCore
import SwiftUI

struct WorkbenchEditor: View {
    @Binding var profile: SoundProfile
    let connectionState: BoardConnectionState
    let onRenameBoard: (String) async -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WorkbenchHeading(connectionState: connectionState, onRenameBoard: onRenameBoard)
                TextField("Profile name", text: $profile.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Profile name")
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) {
                        EqualizerPlot(settings: profile.settings)
                        BandEditor(bands: $profile.settings.bands)
                    }
                    .frame(maxWidth: .infinity)
                    SignalChainInspector(settings: $profile.settings)
                        .frame(width: 230)
                }
                ProfileValidationNotice(profile: profile)
            }
            .padding(22)
        }
        .background(WorkbenchTheme.chassis(for: colorScheme))
    }
}

private struct WorkbenchHeading: View {
    let connectionState: BoardConnectionState
    let onRenameBoard: (String) async -> Void
    @State private var isRenaming = false
    @State private var isShowingFlashSheet = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            ConnectionBadge(state: connectionState)
            if case let .verified(capabilities) = connectionState {
                Button("Rename SoundBox", systemImage: "pencil") { isRenaming = true }
                    .labelStyle(.iconOnly)
                    .popover(isPresented: $isRenaming) {
                        BoardRenameForm(currentName: capabilities.deviceName) { name in
                            isRenaming = false
                            Task { await onRenameBoard(name) }
                        }
                    }
            }
            Spacer()
            Button("Flash Firmware", systemImage: "bolt") { isShowingFlashSheet = true }
                .sheet(isPresented: $isShowingFlashSheet) {
                    FlashFirmwareSheet(connectionState: connectionState)
                }
        }
    }
}

private struct FlashFirmwareSheet: View {
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

private struct BoardRenameForm: View {
    let currentName: String
    let onSubmit: (String) -> Void
    @State private var name: String

    init(currentName: String, onSubmit: @escaping (String) -> Void) {
        self.currentName = currentName
        self.onSubmit = onSubmit
        _name = State(initialValue: currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SoundBox name")
                .font(.headline)
            TextField("SoundBox name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { onSubmit(name) }
            Text("The new name appears in macOS only after the board resets or is replugged.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Apply") { onSubmit(name) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}

private struct ConnectionBadge: View {
    let state: BoardConnectionState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .symbolRenderingMode(.hierarchical)
                .font(.largeTitle)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private extension ConnectionBadge {
    var title: String {
        switch state {
        case .disconnected: String(localized: "SoundBox not connected")
        case .detected: String(localized: "Checking SoundBox…")
        case .verified: String(localized: "SoundBox connected")
        case .mismatched: String(localized: "SoundBox not verified")
        }
    }

    var subtitle: String? {
        guard case let .verified(capabilities) = state else {
            return nil
        }
        let firmware = String(localized: "Firmware \(capabilities.firmwareVersion)")
        return capabilities.deviceName.isEmpty ? firmware : String(localized: "\(capabilities.deviceName) · \(firmware)")
    }

    var iconColor: Color {
        switch state {
        case .disconnected, .detected: .secondary
        case .verified: .green
        case .mismatched: .red
        }
    }
}

private struct ProfileValidationNotice: View {
    let profile: SoundProfile

    var body: some View {
        if let message = validationMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        } else {
            Text("Editing this profile never changes a connected SoundBox.")
                .foregroundStyle(.secondary)
        }
    }
}

private extension ProfileValidationNotice {
    var validationMessage: String? {
        do {
            try profile.validate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
