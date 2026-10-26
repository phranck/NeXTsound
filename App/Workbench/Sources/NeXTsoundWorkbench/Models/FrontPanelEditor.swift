import NeXTsoundCore
import SwiftUI

/// Writes the front panel's edits into the selected profile through the model's edit path.
///
/// Each edit advances the profile's revision, registers its undo and plays on a connected SoundBox.
@MainActor
struct FrontPanelEditor {
    let model: WorkbenchModel
    let undoManager: UndoManager?
}

extension FrontPanelEditor {
    /// The selected profile's settings as they stand.
    var settings: DSPSettings {
        model.profile.settings
    }

    /// A binding to one of the selected profile's settings.
    func binding<Value: Sendable>(_ keyPath: WritableKeyPath<DSPSettings, Value> & Sendable) -> Binding<Value> {
        Binding {
            model.profile.settings[keyPath: keyPath]
        } set: { newValue in
            edit { $0[keyPath: keyPath] = newValue }
        }
    }

    /// A binding to one setting of one of the selected profile's bands.
    func binding<Value: Sendable>(band: Int, _ keyPath: WritableKeyPath<EQBand, Value> & Sendable) -> Binding<Value> {
        Binding {
            model.profile.settings.bands[band][keyPath: keyPath]
        } set: { newValue in
            edit { $0.bands[band][keyPath: keyPath] = newValue }
        }
    }

    /// Puts a band back to how a new profile has it.
    func resetBand(_ band: Int) {
        edit { $0.bands[band] = DSPSettings.defaultBand(at: band) }
    }

    /// The range a fader offers for `parameter`: the one the verified board reports, within the shared range, so the
    /// fader stops where the board does, or the shared range while no board is verified.
    func range(for parameter: DSPParameter) -> ClosedRange<Float> {
        model.boards.state.verifiedCapabilities?.parameterRanges[parameter]?.clamped(to: parameter.bounds) ?? parameter.bounds
    }
}

private extension FrontPanelEditor {
    func edit(_ change: (inout DSPSettings) -> Void) {
        var proposed = model.profile
        change(&proposed.settings)
        model.updateProfile(proposed, undoManager: undoManager)
    }
}
