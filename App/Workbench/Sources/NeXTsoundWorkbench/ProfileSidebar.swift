import Foundation
import NeXTsoundCore
import SwiftUI

struct ProfileSidebar: View {
    let model: WorkbenchModel
    let undoManager: UndoManager?

    var body: some View {
        List(selection: selection) {
            ProfileListSection(profiles: model.library.profiles)
            SpeakerSection(speaker: model.profile.speaker)
            if let status = model.storageStatus {
                StorageStatusSection(status: status)
            }
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

private struct StorageStatusSection: View {
    let status: String

    var body: some View {
        Section {
            Text(status)
                .foregroundStyle(.secondary)
        }
    }
}
