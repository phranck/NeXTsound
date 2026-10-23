import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct LibraryEditorTests {
    @Test func selectingALineSelectsItsProfile() throws {
        let model = try modelWithThreeProfiles()
        let editor = LibraryEditor(model: model, undoManager: nil)
        editor.select(at: 2)
        #expect(model.library.selectedID == model.library.profiles[2].id)
        editor.moveSelection(by: -1)
        #expect(editor.selectedIndex == 1)
        editor.moveSelection(by: 5)
        #expect(editor.selectedIndex == 2)
        editor.select(at: 9)
        #expect(editor.selectedIndex == 2)
    }

    @Test func renamingGoesThroughTheProfilesEditPath() throws {
        let model = try modelWithThreeProfiles()
        let undoManager = UndoManager()
        let revision = model.profile.revision
        LibraryEditor(model: model, undoManager: undoManager).rename(to: "Late Night")
        #expect(model.profile.name == "Late Night")
        #expect(model.profile.revision > revision)
        undoManager.undo()
        #expect(model.profile.name == "First")
    }

    @Test func keepingTheNameChangesNothing() throws {
        let model = try modelWithThreeProfiles()
        let undoManager = UndoManager()
        model.errorMessage = "Earlier error"
        let revision = model.library.revision
        LibraryEditor(model: model, undoManager: undoManager).rename(to: "First")
        #expect(model.library.revision == revision)
        #expect(!undoManager.canUndo)
        #expect(model.errorMessage == "Earlier error")
    }

    @Test func aSpeakerChoiceReachesTheSelectedProfile() throws {
        let model = try modelWithThreeProfiles()
        let driver = DriverRecord(name: "Dayton Audio CE41N-4")
        let editor = LibraryEditor(model: model, undoManager: nil)
        editor.selectSpeaker(driver)
        #expect(model.profile.speaker?.name == "Dayton Audio CE41N-4")
        editor.selectSpeaker(nil)
        #expect(model.profile.speaker == nil)
    }

    @Test func theProfileKeysAddDeleteImportAndExport() throws {
        let model = try modelWithThreeProfiles()
        let undoManager = UndoManager()
        let editor = LibraryEditor(model: model, undoManager: undoManager)
        editor.addProfile()
        #expect(model.library.profiles.count == 4)
        #expect(model.profile.name == "New profile")
        editor.deleteProfile()
        #expect(model.library.profiles.map(\.name) == ["First", "Second", "Third"])
        #expect(undoManager.undoActionName == "Delete profile")
        editor.importProfile()
        #expect(model.isImporting)
        editor.exportProfile()
        #expect(model.isExporting)
    }

    @Test func theLastProfileCannotBeDeleted() throws {
        let profile = SoundProfile(name: "Only")
        let model = try WorkbenchModel(library: ProfileLibrary(profiles: [profile], selectedID: profile.id))
        let editor = LibraryEditor(model: model, undoManager: nil)
        #expect(!editor.canDeleteProfile)
        editor.addProfile()
        #expect(editor.canDeleteProfile)
    }
}

@MainActor
private func modelWithThreeProfiles() throws -> WorkbenchModel {
    let profiles = [SoundProfile(name: "First"), SoundProfile(name: "Second"), SoundProfile(name: "Third")]
    return try WorkbenchModel(library: ProfileLibrary(profiles: profiles, selectedID: profiles[0].id))
}
