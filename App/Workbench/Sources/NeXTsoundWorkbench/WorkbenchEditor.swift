import NeXTsoundCore
import SwiftUI
import UniformTypeIdentifiers

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
                    FlashFirmwareSheet(applicationSerial: applicationSerial)
                }
        }
    }
}

private extension WorkbenchHeading {
    var applicationSerial: String? {
        guard case let .verified(capabilities) = connectionState else {
            return nil
        }
        return capabilities.serial
    }
}

private struct FlashFirmwareSheet: View {
    @State private var model: FlashFirmwareSheetModel
    @State private var isChoosingFirmware = false
    @Environment(\.dismiss) private var dismiss

    init(applicationSerial: String?) {
        _model = State(initialValue: FlashFirmwareSheetModel(target: FlashTarget(applicationSerial: applicationSerial)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flash firmware")
                .font(.headline)
            if model.target.applicationSerial == nil {
                Text("Put the SoundBox into BOOTSEL mode before continuing: hold its BOOTSEL button while connecting the USB cable.")
                    .foregroundStyle(.secondary)
            }
            FirmwareFileRow(url: model.selectedFirmwareURL) { isChoosingFirmware = true }
            FlashOutcomeView(outcome: model.outcome)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                Button("Flash") { model.flash() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selectedFirmwareURL == nil || model.isRunning || model.outcome == .succeeded)
            }
        }
        .padding(16)
        .frame(width: 420)
        .fileImporter(isPresented: $isChoosingFirmware, allowedContentTypes: [UTType(filenameExtension: "uf2") ?? .data]) { result in
            guard case let .success(url) = result else {
                return
            }
            model.selectedFirmwareURL = url
        }
    }
}

private struct FirmwareFileRow: View {
    let url: URL?
    let onChoose: () -> Void

    var body: some View {
        HStack {
            Text(url?.lastPathComponent ?? String(localized: "No firmware image selected"))
                .foregroundStyle(url == nil ? .secondary : .primary)
            Spacer()
            Button("Choose…") { onChoose() }
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
            Label {
                Text(phase.statusText.prefix(1).capitalized + phase.statusText.dropFirst() + "…")
            } icon: {
                ProgressView()
                    .controlSize(.small)
            }
        case .succeeded:
            Label("Firmware flashed and verified.", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
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
