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

struct ProfileListLinesTests {
    @Test func theListKeepsTheSelectedProfileInView() {
        #expect(ProfileListLines.firstVisible(previous: 0, selected: 3, count: 12) == 0)
        #expect(ProfileListLines.firstVisible(previous: 0, selected: 9, count: 12) == 3)
        #expect(ProfileListLines.firstVisible(previous: 5, selected: 2, count: 12) == 2)
        #expect(ProfileListLines.firstVisible(previous: 4, selected: 1, count: 3) == 0)
    }

    @Test func aClickFindsTheLineUnderIt() {
        let linePitch = CGFloat(DotMatrixMetrics.linePitch) * DotMatrixMetrics.pitch
        #expect(ProfileListLines.lineIndex(at: 0) == 0)
        #expect(ProfileListLines.lineIndex(at: linePitch - 0.5) == 0)
        #expect(ProfileListLines.lineIndex(at: linePitch) == 1)
        #expect(ProfileListLines.lineIndex(at: 7 * linePitch - 0.5) == 6)
        #expect(ProfileListLines.lineIndex(at: 7 * linePitch) == nil)
        #expect(ProfileListLines.lineIndex(at: -1) == nil)
    }

    @Test func aRenamedNameScrollsSoTheCaretKeepsACell() {
        let start = ProfileListLines.renameLine(text: "Desk", caret: 4, cells: 13, showsCursor: true)
        #expect(start == DotMatrixLine(text: ">Desk", cursorCell: 5))
        let scrolled = ProfileListLines.renameLine(text: "Desk Monitor Mix", caret: 16, cells: 13, showsCursor: true)
        #expect(scrolled == DotMatrixLine(text: ">Monitor Mix", cursorCell: 12))
        let hidden = ProfileListLines.renameLine(text: "Desk", caret: 2, cells: 13, showsCursor: false)
        #expect(hidden.cursorCell == nil)
    }
}

struct LibraryReadoutLinesTests {
    @Test func theSpeakerBreaksBetweenItsWordsAndKeepsItsModel() {
        #expect(LibraryReadoutLines.speaker("Dayton Audio CE41N-4", cells: 13) == [
            DotMatrixLine(text: "Dayton Audio"),
            DotMatrixLine(text: "CE41N-4"),
        ])
        #expect(LibraryReadoutLines.speaker("Tectonic Audio Labs TEBM28C10-4BE", cells: 13) == [
            DotMatrixLine(text: "Tectonic"),
            DotMatrixLine(text: "TEBM28C10-4BE"),
        ])
    }

    @Test func noSpeakerReadsNotSelectedAStepDimmer() {
        let lines = LibraryReadoutLines.speaker(nil, cells: 13)
        #expect(lines.allSatisfy { $0.tone == .normal })
        #expect(lines.map(\.text).joined(separator: " ") == String(localized: "Not selected"))
    }

    @Test func theSoundBoxShowsItsNameOnlyWhileVerified() {
        var capabilities = DeviceCapabilities(serial: "D4CDD489AFE28CC5", firmwareVersion: "1.2.0")
        capabilities.deviceName = "Bedroom SoundBox"
        #expect(LibraryReadoutLines.soundBox(.verified(capabilities)) == DotMatrixLine(text: "Bedroom SoundBox"))
        #expect(LibraryReadoutLines.soundBox(.disconnected).tone == .normal)
        #expect(LibraryReadoutLines.soundBox(.mismatched("Wrong firmware")) == LibraryReadoutLines.soundBox(.detected))
    }
}

@MainActor
private func modelWithThreeProfiles() throws -> WorkbenchModel {
    let profiles = [SoundProfile(name: "First"), SoundProfile(name: "Second"), SoundProfile(name: "Third")]
    return try WorkbenchModel(library: ProfileLibrary(profiles: profiles, selectedID: profiles[0].id))
}
