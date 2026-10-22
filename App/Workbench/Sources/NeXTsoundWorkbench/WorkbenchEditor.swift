import NeXTsoundCore
import SwiftUI

struct WorkbenchEditor: View {
    @Binding var profile: SoundProfile
    let board: BoardHeading
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WorkbenchHeading(board: board)
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

/// What the editor header shows about the connected SoundBox, and the board actions it offers.
struct BoardHeading {
    /// The connection state the badge and the board actions follow.
    let connectionState: BoardConnectionState
    /// Whether the board starts with the settings it plays; nil hides the line.
    let storageStatus: String?
    /// Enables "Save to SoundBox".
    let canSave: Bool
    /// Writes a new persisted name to the board.
    let onRename: (String) async -> Void
    /// Applies the current profile to the board and saves it there.
    let onSave: () async -> Void
}

private struct WorkbenchHeading: View {
    let board: BoardHeading
    @State private var isRenaming = false
    @State private var isShowingFlashSheet = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            ConnectionBadge(state: board.connectionState, storageStatus: board.storageStatus)
            if case let .verified(capabilities) = board.connectionState {
                Button("Rename SoundBox", systemImage: "pencil") { isRenaming = true }
                    .labelStyle(.iconOnly)
                    .popover(isPresented: $isRenaming) {
                        BoardRenameForm(currentName: capabilities.deviceName) { name in
                            isRenaming = false
                            Task { await board.onRename(name) }
                        }
                    }
            }
            Spacer()
            HStack {
                if case .verified = board.connectionState {
                    Button {
                        Task { await board.onSave() }
                    } label: {
                        Label("Save to SoundBox", systemImage: "memorychip")
                            .frame(maxHeight: .infinity)
                    }
                    .disabled(!board.canSave)
                    .help("Save the current profile on the SoundBox, so it starts with it")
                }
                Button {
                    isShowingFlashSheet = true
                } label: {
                    Label("Flash Firmware", systemImage: "bolt")
                        .frame(maxHeight: .infinity)
                }
            }
            // The two symbols differ in height; both labels take the taller one's, so the buttons match.
            .fixedSize(horizontal: false, vertical: true)
            .sheet(isPresented: $isShowingFlashSheet) {
                FlashFirmwareSheet(connectionState: board.connectionState)
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
    let storageStatus: String?

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
                if let storageStatus {
                    Text(storageStatus)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private extension ConnectionBadge {
    var title: String {
        state.title
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
            Text("A connected SoundBox plays every edit right away.")
                .foregroundStyle(.secondary)
        }
    }
}

private extension ProfileValidationNotice {
    var validationMessage: String? {
        profile.validationProblem
    }
}
