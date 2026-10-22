import Observation

/// What the front panel shows of a save to the SoundBox: the SAVE LED's flash and, for a moment after it, the
/// message that the settings are saved.
@MainActor
@Observable
final class FrontPanelSaveFeedback {
    /// Whether the SAVE LED is lit. It lights the moment SAVE is pressed and drains away shortly after.
    private(set) var ledIsLit = false
    /// Whether the display reports the last save as done.
    private(set) var showsSuccess = false

    @ObservationIgnored private var saves = 0
}

extension FrontPanelSaveFeedback {
    /// How long the LED stays lit before it drains.
    static let ledHold = Duration.milliseconds(200)
    /// How long the display reports a finished save.
    static let successHold = Duration.milliseconds(2500)

    /// Saves the profile to the connected SoundBox, as SAVE does. It does nothing while no board can save, and a
    /// failure leaves its reason in the model's error.
    func save(with model: WorkbenchModel) async {
        guard model.canSaveToBoard else {
            return
        }
        saves += 1
        let save = saves
        ledIsLit = true
        showsSuccess = false
        Task {
            try? await Task.sleep(for: Self.ledHold)
            if saves == save {
                ledIsLit = false
            }
        }
        model.errorMessage = nil
        await model.saveToBoard()
        guard
            saves == save,
            model.errorMessage == nil
        else {
            return
        }
        showsSuccess = true
        try? await Task.sleep(for: Self.successHold)
        if saves == save {
            showsSuccess = false
        }
    }
}
