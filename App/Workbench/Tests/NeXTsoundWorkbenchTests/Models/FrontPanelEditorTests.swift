import Foundation
import NeXTsoundCore
import SwiftUI
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct FrontPanelEditorTests {
    @Test func anEditFromAControlGoesThroughTheProfilesEditPath() {
        let model = WorkbenchModel()
        let revision = model.profile.revision
        FrontPanelEditor(model: model, undoManager: nil).binding(band: 2, \.gainDb).wrappedValue = 4
        #expect(model.profile.settings.bands[2].gainDb == 4)
        #expect(model.profile.revision > revision)
    }

    @Test func anEditFromAControlCanBeUndone() {
        let model = WorkbenchModel()
        let undoManager = UndoManager()
        let before = model.profile.settings
        FrontPanelEditor(model: model, undoManager: undoManager).binding(\.attenuationDb).wrappedValue = -12
        undoManager.undo()
        #expect(model.profile.settings == before)
    }

    @Test func resettingABandRestoresTheBandOfANewProfile() {
        let model = WorkbenchModel()
        let editor = FrontPanelEditor(model: model, undoManager: nil)
        editor.binding(band: 1, \.gainDb).wrappedValue = 6
        editor.binding(band: 1, \.isEnabled).wrappedValue = false
        editor.resetBand(1)
        #expect(model.profile.settings.bands[1] == DSPSettings.defaultBand(at: 1))
    }
}
