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

    /// A fader stops where the verified board does, and travels the shared range while no board is verified.
    @Test func aFaderOffersTheRangeTheVerifiedBoardTakes() async throws {
        let unverified = FrontPanelEditor(model: WorkbenchModel(), undoManager: nil)
        #expect(unverified.range(for: .attenuation) == DSPParameter.attenuation.bounds)
        var capabilities = fixtureCapabilities()
        capabilities.parameterRanges[.attenuation] = -80 ... 0
        let model = try await WorkbenchModel(boards: verifiedMonitor(FakeBoardTransport(behavior: .success(capabilities))))
        #expect(FrontPanelEditor(model: model, undoManager: nil).range(for: .attenuation) == -80 ... 0)
    }
}
