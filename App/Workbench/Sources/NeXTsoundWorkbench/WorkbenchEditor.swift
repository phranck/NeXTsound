import NeXTsoundCore
import SwiftUI

struct WorkbenchEditor: View {
    @Binding var profile: SoundProfile
    let connectionState: BoardConnectionState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WorkbenchHeading(connectionState: connectionState)
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

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NeXTsound")
                    .font(.title.bold())
                Text("Mono sound workbench")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ConnectionBadge(state: connectionState)
        }
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
        case .disconnected: "SoundBox not connected"
        case .detected: "Checking SoundBox…"
        case .verified: "SoundBox connected"
        case .mismatched: "SoundBox not verified"
        }
    }

    var subtitle: String? {
        guard case let .verified(capabilities) = state else {
            return nil
        }
        return "Firmware \(capabilities.firmwareVersion)"
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
