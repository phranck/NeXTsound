import Foundation
import NeXTsoundCore
import SwiftUI

struct ProfileSidebar: View {
    let profile: SoundProfile
    let fileURL: URL?
    let applyPreset: (FactoryPreset) -> Void

    var body: some View {
        List {
            Section("Profile") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.name.isEmpty ? "Untitled" : profile.name)
                        .font(.headline)
                    Text(fileURL?.lastPathComponent ?? "Unsaved document")
                        .foregroundStyle(.secondary)
                    Text("Revision \(profile.revision)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
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
            Section("Speaker") {
                Text(profile.speaker?.name ?? "Not selected")
                Text("Speaker safety is unverified.")
                    .foregroundStyle(.secondary)
            }
            Section("Enclosure") {
                Text(profile.enclosure?.name ?? "Not selected")
                EnclosureVolumeLabel(volume: profile.enclosure?.volume)
            }
        }
        .listStyle(.sidebar)
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
