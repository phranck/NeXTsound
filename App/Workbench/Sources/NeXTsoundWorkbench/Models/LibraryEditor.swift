import Foundation
import NeXTsoundCore

/// Carries out what the Library panel and the File menu ask of the library through the model's edit path, so every
/// change registers its undo and is saved like any other edit.
@MainActor
struct LibraryEditor {
    let model: WorkbenchModel
    let undoManager: UndoManager?
}

extension LibraryEditor {
    /// The library's profiles in their order.
    var profiles: [SoundProfile] {
        model.library.profiles
    }

    /// The identifier of the selected profile.
    var selectedID: UUID {
        model.library.selectedID
    }

    /// The selected profile.
    var selectedProfile: SoundProfile {
        model.profile
    }

    /// The position of the selected profile among `profiles`.
    var selectedIndex: Int {
        profiles.firstIndex { $0.id == selectedID } ?? 0
    }

    /// Whether the selected profile can be deleted. The last one cannot, so the display always names a profile.
    var canDeleteProfile: Bool {
        profiles.count > 1
    }

    /// Selects the profile at `index`. An index outside the list selects nothing.
    func select(at index: Int) {
        guard profiles.indices.contains(index) else {
            return
        }
        model.selectProfile(profiles[index].id)
    }

    /// Selects the profile `step` places from the selected one, stopping at either end of the list.
    func moveSelection(by step: Int) {
        select(at: min(max(selectedIndex + step, 0), profiles.count - 1))
    }

    /// Gives the selected profile a new name. A name equal to the current one changes nothing, so it leaves the
    /// display's latest message standing.
    func rename(to name: String) {
        guard name != selectedProfile.name else {
            return
        }
        var proposed = selectedProfile
        proposed.name = name
        model.updateProfile(proposed, undoManager: undoManager)
    }

    /// Sets the selected profile's speaker, or clears it.
    func selectSpeaker(_ driver: DriverRecord?) {
        model.selectSpeaker(driver, undoManager: undoManager)
    }

    /// Adds a new profile and selects it.
    func addProfile() {
        model.addProfile(undoManager: undoManager)
    }

    /// Deletes the selected profile and selects the first one.
    func deleteProfile() {
        model.removeProfile(undoManager: undoManager)
    }

    /// Asks the main window to show the panel that imports a profile file.
    func importProfile() {
        model.isImporting = true
    }

    /// Asks the main window to show the panel that exports the selected profile to a file.
    func exportProfile() {
        model.isExporting = true
    }
}
