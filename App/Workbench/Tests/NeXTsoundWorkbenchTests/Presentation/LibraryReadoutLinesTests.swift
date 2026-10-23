import CoreGraphics
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

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

    /// A name wider than one line breaks between its words over the readout's two lines, so all of it shows.
    @Test func theSoundBoxNameBreaksBetweenItsWords() {
        var capabilities = DeviceCapabilities(serial: "D4CDD489AFE28CC5", firmwareVersion: "1.2.0")
        capabilities.deviceName = "Bedroom SoundBox"
        #expect(LibraryReadoutLines.soundBox(.verified(capabilities), cells: 13) == [
            DotMatrixLine(text: "Bedroom"),
            DotMatrixLine(text: "SoundBox"),
        ])
        #expect(LibraryReadoutLines.soundBox(.disconnected, cells: 13) == [
            DotMatrixLine(text: String(localized: "No SoundBox"), tone: .normal),
        ])
    }
}
