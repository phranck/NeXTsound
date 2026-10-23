import CoreGraphics
import Testing
@testable import NeXTsoundWorkbench

struct DotMatrixTests {
    @Test func everyGlyphHasSevenRowsOfFiveColumns() {
        for (character, pattern) in DotMatrixGlyphs.patterns {
            #expect(pattern.count == DotMatrixFont.glyphRows, "\(character)")
            #expect(pattern.allSatisfy { $0 < 1 << DotMatrixFont.glyphColumns }, "\(character)")
        }
    }

    @Test func germanLettersAndThePanelsSymbolsHaveTheirOwnGlyphs() {
        for character in "ÄÖÜäöüß/>!_…" {
            #expect(DotMatrixGlyphs.patterns[character] != nil, "\(character)")
        }
    }

    @Test func charactersWithoutAGlyphFallBack() {
        #expect(DotMatrixFont.pattern(for: "ǹ") == DotMatrixFont.pattern(for: "n"))
        #expect(DotMatrixFont.pattern(for: "音") == DotMatrixFont.pattern(for: "?"))
        #expect(DotMatrixFont.pattern(for: " ").allSatisfy { $0 == 0 })
    }

    @Test func charactersStandOneEmptyColumnApart() {
        let masks = DotMatrixFont.columnMasks(for: "AB")
        #expect(masks.count == DotMatrixMetrics.columns(forCells: 2))
        #expect(masks[DotMatrixFont.glyphColumns] == 0)
    }

    @Test func aReadoutOfFiveCellsMeasuresWhatTheMockupMeasures() {
        #expect(DotMatrixLinesLayout(cells: 5).size == CGSize(width: 61.5, height: 17.5))
        #expect(DotMatrixLinesLayout(cells: 5, lines: 2).size.height == 17.5 + 9 * DotMatrixMetrics.pitch)
    }

    @Test func alignmentCutsAndPadsATextToItsCells() {
        #expect(DotMatrixAlignment.leading.fit("Bedroom", cells: 4) == "Bedr")
        #expect(DotMatrixAlignment.trailing.fit("12345", cells: 3) == "345")
        #expect(DotMatrixAlignment.trailing.fit("7", cells: 3) == "  7")
        #expect(DotMatrixAlignment.leading.fit("Bedroom", cells: -1).isEmpty)
    }
}
