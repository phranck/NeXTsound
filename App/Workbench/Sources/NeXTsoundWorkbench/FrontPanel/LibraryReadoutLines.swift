import CoreGraphics
import Foundation
import NeXTsoundCore

/// Which of the profiles the Library's list shows, and how each of its lines reads.
enum ProfileListLines {
    /// The list's lines.
    static let visibleLines = 7
    /// The mark before the selected profile, a cell wide.
    static let marker = ">"

    /// The first profile in view once `selected` is kept in view, moving the view as little as it can from
    /// `previous`.
    static func firstVisible(previous: Int, selected: Int, count: Int) -> Int {
        let keepsSelection = max(min(previous, selected), selected - visibleLines + 1)
        return max(0, min(keepsSelection, count - visibleLines))
    }

    /// The line at `offset` points below the top of the list's dots, or nil below the last line and above the first.
    static func lineIndex(at offset: CGFloat) -> Int? {
        guard offset >= 0 else {
            return nil
        }
        let line = Int((offset / (CGFloat(DotMatrixMetrics.linePitch) * DotMatrixMetrics.pitch)).rounded(.down))
        return line < visibleLines ? line : nil
    }

    /// The line of a profile: marked and bright while it is selected, indented and a step dimmer otherwise.
    static func line(name: String, isSelected: Bool) -> DotMatrixLine {
        isSelected ? DotMatrixLine(text: marker + name) : DotMatrixLine(text: " " + name, tone: .normal)
    }

    /// The selected profile's line while it is renamed: the marker, then as much of the typed name as fits, scrolled
    /// so that the caret always has a cell of its own.
    ///
    /// - Parameters:
    ///   - text: The name as typed so far.
    ///   - caret: The caret's position in `text`, in characters.
    ///   - cells: The line's character cells.
    ///   - showsCursor: Whether the blinking cursor is on.
    static func renameLine(text: String, caret: Int, cells: Int, showsCursor: Bool) -> DotMatrixLine {
        let nameCells = max(cells - marker.count, 1)
        let firstShown = max(0, caret - nameCells + 1)
        let shown = String(text.dropFirst(firstShown).prefix(nameCells))
        return DotMatrixLine(text: marker + shown, cursorCell: showsCursor ? marker.count + caret - firstShown : nil)
    }
}

/// How the Library panel's speaker and SoundBox readouts read.
enum LibraryReadoutLines {
    /// The speaker readout's lines.
    static let speakerLines = 2

    /// The speaker's name broken between its words over the readout's lines, or Not selected a step dimmer without
    /// one. A name that needs more lines than the readout has keeps its last line, because a driver's name ends with
    /// its model.
    static func speaker(_ name: String?, cells: Int) -> [DotMatrixLine] {
        let text = name ?? String(localized: "Not selected")
        var lines = DotMatrixWrap.lines(of: text, width: cells, firstPrefix: "", laterPrefix: "")
        if lines.count > speakerLines {
            lines = Array(lines.prefix(speakerLines - 1)) + [lines[lines.count - 1]]
        }
        return lines.map { DotMatrixLine(text: $0, tone: name == nil ? .normal : .bright) }
    }

    /// The SoundBox's name while the board is verified, and a step dimmer what keeps the name from showing otherwise.
    static func soundBox(_ state: BoardConnectionState) -> DotMatrixLine {
        switch state {
        case let .verified(capabilities):
            DotMatrixLine(text: capabilities.deviceName)
        case .disconnected:
            DotMatrixLine(text: String(localized: "No SoundBox"), tone: .normal)
        case .detected, .mismatched:
            DotMatrixLine(text: String(localized: "Not verified"), tone: .normal)
        }
    }
}
