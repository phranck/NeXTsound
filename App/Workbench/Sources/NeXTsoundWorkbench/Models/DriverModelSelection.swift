import Foundation
import NeXTsoundCore

/// The driver model the Driver Models window has selected, and the edit in progress on it.
///
/// The draft is a copy of the selected driver model that the form edits. It reaches the library only through
/// `apply(to:)`, which validates it first, and it starts over from the library's copy whenever the selection or the
/// library changes.
@MainActor
struct DriverModelSelection {
    private(set) var selectedID: UUID?
    /// The selected driver model as the form edits it, or nil without a selection.
    var draft: DriverRecord?
    /// Why the last Apply was refused, or nil.
    private(set) var validationError: String?
}

extension DriverModelSelection {
    /// Whether a driver model is selected for Delete to remove.
    var canDelete: Bool {
        selectedID != nil
    }

    /// Selects the driver model with `id` among `drivers` and starts its draft over from it.
    mutating func select(_ id: UUID?, in drivers: [DriverRecord]) {
        selectedID = id
        refresh(from: drivers)
    }

    /// Starts the draft over from the selected driver model in `drivers`, or ends it when that model is gone.
    mutating func refresh(from drivers: [DriverRecord]) {
        guard
            let selectedID,
            let driver = drivers.first(where: { $0.id == selectedID })
        else {
            draft = nil
            return
        }
        draft = driver
        validationError = nil
    }

    /// Saves the draft to `library` once it validates, and keeps the reason otherwise.
    mutating func apply(to library: DriverLibraryModel) {
        guard let draft else {
            return
        }
        do {
            try draft.validate()
            library.updateDriver(draft)
            validationError = nil
        } catch {
            validationError = error.localizedDescription
        }
    }

    /// Removes the selected driver model from `library` and selects the first one that remains.
    mutating func deleteSelected(from library: DriverLibraryModel) {
        guard let selectedID else {
            return
        }
        let remaining = library.drivers.filter { $0.id != selectedID }
        library.removeDriver(selectedID)
        select(remaining.first?.id, in: library.drivers)
    }
}
