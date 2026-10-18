import Foundation
import NeXTsoundCore
import SwiftUI

struct ProfileSidebar: View {
    let model: WorkbenchModel
    let undoManager: UndoManager?

    var body: some View {
        List(selection: selection) {
            ProfileListSection(profiles: model.library.profiles)
            PresetsSection { model.applyPreset($0, undoManager: undoManager) }
            SpeakerSection(speaker: model.profile.speaker)
            EnclosureSection(enclosure: model.profile.enclosure)
            BoardStatusSection(state: model.boards.state)
            StorageStatusSection(status: model.storageStatus)
        }
        .listStyle(.sidebar)
    }
}

private extension ProfileSidebar {
    var selection: Binding<UUID?> {
        Binding(get: { model.library.selectedID }, set: { identifier in
            if let identifier {
                model.selectProfile(identifier)
            }
        })
    }
}

private struct ProfileListSection: View {
    let profiles: [SoundProfile]

    var body: some View {
        Section("Profiles") {
            ForEach(profiles) { profile in
                Text(profile.name.isEmpty ? "Untitled" : profile.name)
                    .tag(profile.id)
            }
        }
    }
}

private struct PresetsSection: View {
    let applyPreset: (FactoryPreset) -> Void

    var body: some View {
        Section("Starting presets") {
            ForEach(FactoryPreset.allCases) { preset in
                Button { applyPreset(preset) } label: {
                    Text(preset.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .help("Apply the muted \(preset.name) settings without replacing this profile's speaker or enclosure.")
            }
        }
    }
}

private struct SpeakerSection: View {
    let speaker: SpeakerRecord?

    var body: some View {
        Section("Speaker") {
            Text(speaker?.name ?? "Not selected")
            Text("Speaker safety is unverified.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct EnclosureSection: View {
    let enclosure: EnclosureRecord?

    var body: some View {
        Section("Enclosure") {
            Text(enclosure?.name ?? "Not selected")
            EnclosureVolumeLabel(volume: enclosure?.volume)
        }
    }
}

private struct EnclosureVolumeLabel: View {
    let volume: EnclosureVolume?

    var body: some View {
        if let volume {
            Text("\(volume.netLiters.formatted(.number.precision(.fractionLength(0 ... 3)))) L net")
                .foregroundStyle(.secondary)
        } else {
            Text("Volume not set")
                .foregroundStyle(.secondary)
        }
    }
}

private struct BoardStatusSection: View {
    let state: BoardConnectionState

    var body: some View {
        Section("SoundBox") {
            switch state {
            case .disconnected:
                Label("Not connected", systemImage: "cable.connector.slash")
                    .foregroundStyle(.secondary)
            case .detected:
                Label("Checking device…", systemImage: "cable.connector")
                    .foregroundStyle(.secondary)
            case let .verified(capabilities):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Connected", systemImage: "cable.connector")
                    Text("Serial \(capabilities.serial)")
                        .foregroundStyle(.secondary)
                    Text("Firmware \(capabilities.firmwareVersion)")
                        .foregroundStyle(.secondary)
                }
            case let .mismatched(reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct StorageStatusSection: View {
    let status: String

    var body: some View {
        Section {
            Text(status)
                .foregroundStyle(.secondary)
        }
    }
}
