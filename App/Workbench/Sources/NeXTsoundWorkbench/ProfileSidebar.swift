import Foundation
import NeXTsoundCore
import SwiftUI

struct ProfileSidebar: View {
    let model: WorkbenchModel
    let driverLibrary: DriverLibraryModel
    let undoManager: UndoManager?

    var body: some View {
        List(selection: selection) {
            ProfileListSection(profiles: model.library.profiles)
            SpeakerSection(speaker: model.profile.speaker, drivers: driverLibrary.drivers, onSelect: selectSpeaker)
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

    func selectSpeaker(_ driver: DriverRecord?) {
        model.selectSpeaker(driver, undoManager: undoManager)
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
    let drivers: [DriverRecord]
    let onSelect: (DriverRecord?) -> Void

    var body: some View {
        Section("Speaker") {
            Picker("Speaker", selection: selection) {
                Text("Not selected").tag(UUID?.none)
                ForEach(drivers) { driver in
                    Text(driver.name).tag(Optional(driver.id))
                }
            }
            .labelsHidden()
            Text("Speaker safety is unverified.")
                .foregroundStyle(.secondary)
        }
    }
}

private extension SpeakerSection {
    var selection: Binding<UUID?> {
        Binding(get: { speaker?.id }, set: { identifier in
            onSelect(drivers.first(where: { $0.id == identifier }))
        })
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
