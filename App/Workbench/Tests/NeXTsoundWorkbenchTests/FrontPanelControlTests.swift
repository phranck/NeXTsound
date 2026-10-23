import Foundation
import NeXTsoundCore
import SwiftUI
import Testing
@testable import NeXTsoundWorkbench

struct KeyBankNavigationTests {
    @Test func theArrowKeysMoveOneKeyAndWrapAroundAtTheEnds() {
        #expect(KeyBankNavigation.index(after: 0, step: 1, count: 5) == 1)
        #expect(KeyBankNavigation.index(after: 4, step: 1, count: 5) == 0)
        #expect(KeyBankNavigation.index(after: 0, step: -1, count: 5) == 4)
        #expect(KeyBankNavigation.steps[.rightArrow] == 1)
        #expect(KeyBankNavigation.steps[.downArrow] == 1)
        #expect(KeyBankNavigation.steps[.leftArrow] == -1)
        #expect(KeyBankNavigation.steps[.upArrow] == -1)
    }
}

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

@MainActor
struct MomentaryKeyBankTests {
    /// Two captions as wide as their keys stand slanted, so their glyphs keep four times as far apart as they do on one
    /// level line. A caption's glyphs are the pixels it changes against a render of the bank without captions, so the
    /// keys and their frame drop out.
    @Test func neighboringCaptionsStandClearOfEachOther() throws {
        let bare = try RenderedPixels(Self.bank(captions: ["", ""]))
        let left = try RenderedPixels(Self.bank(captions: ["DELETE", ""])).changes(against: bare)
        let right = try RenderedPixels(Self.bank(captions: ["", "IMPORT"])).changes(against: bare)
        try #require(!left.isEmpty)
        try #require(!right.isEmpty)
        let distance = Self.closestDistance(between: left, and: right)
        #expect(distance >= Self.minimumDistance, "The captions' glyphs are \(distance) device pixels apart.")
    }
}

private extension MomentaryKeyBankTests {
    /// Four points in device pixels at scale 2. On one level line, two words as wide as their keys keep one point
    /// apart.
    static let minimumDistance = 8.0

    static func bank(captions: [String]) -> MomentaryKeyBank {
        MomentaryKeyBank(keys: captions.enumerated().map { index, caption in
            MomentaryKey(id: "key \(index)", caption: caption, name: Text(verbatim: caption)) {}
        })
    }

    /// The smallest distance in device pixels between a pixel of one set and a pixel of the other.
    static func closestDistance(between first: [PixelPosition], and second: [PixelPosition]) -> Double {
        var closest = Double.infinity
        for one in first {
            for other in second {
                let columns = Double(one.column - other.column)
                let rows = Double(one.row - other.row)
                closest = min(closest, (columns * columns + rows * rows).squareRoot())
            }
        }
        return closest
    }
}

/// A pixel's place in a render, counted from the top leading corner.
private struct PixelPosition {
    let column: Int
    let row: Int
}

private extension RenderedPixels {
    /// How far a channel may differ between two renders of the same view before the pixel counts as changed.
    static let changeThreshold = 24

    /// The pixels that differ from the same pixel of another render of the same size.
    func changes(against other: RenderedPixels) -> [PixelPosition] {
        var positions: [PixelPosition] = []
        for row in 0 ..< height {
            for column in 0 ..< width {
                let mine = pixel(column: column, row: row)
                let theirs = other.pixel(column: column, row: row)
                let difference = max(abs(mine.red - theirs.red), abs(mine.green - theirs.green), abs(mine.blue - theirs.blue))
                if difference > Self.changeThreshold {
                    positions.append(PixelPosition(column: column, row: row))
                }
            }
        }
        return positions
    }
}
