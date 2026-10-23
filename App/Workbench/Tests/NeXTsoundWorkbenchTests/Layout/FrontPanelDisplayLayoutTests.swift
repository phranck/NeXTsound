import Testing
@testable import NeXTsoundWorkbench

struct FrontPanelDisplayLayoutTests {
    @Test func gainFallsOnTheCurvesRowsAroundZeroDecibels() {
        #expect(FrontPanelDisplayLayout.row(decibels: 0, rows: 97) == 48)
        #expect(FrontPanelDisplayLayout.row(decibels: FrontPanelDisplayLayout.decibelRange, rows: 97) == 0)
        #expect(FrontPanelDisplayLayout.row(decibels: 100, rows: 97) == 0)
        #expect(FrontPanelDisplayLayout.row(decibels: -100, rows: 97) == 96)
        #expect(FrontPanelDisplayLayout.row(decibels: .nan, rows: 97) == 48)
    }

    @Test func theFrequencyRangeSpansTheCurvesColumns() {
        #expect(FrontPanelDisplayLayout.column(frequencyHz: 20, columns: 343) == 0)
        #expect(FrontPanelDisplayLayout.column(frequencyHz: 20000, columns: 343) == 342)
        #expect(FrontPanelDisplayLayout.column(frequencyHz: 1000, columns: 343).map { (1 ..< 342).contains($0) } == true)
    }

    @Test func theCurveKeepsTwoColumnsOnANarrowDisplay() {
        #expect(FrontPanelDisplayLayout.graphColumns(displayColumns: 10) == 2)
        #expect(FrontPanelDisplayLayout.curveColumns(graphColumns: 10) == 2)
    }

    /// The curve's rows are odd in number, so 0 dB falls on the middle row and the gains above and below it get as
    /// many rows each.
    @Test func zeroDecibelsFallsOnTheCurvesMiddleRow() {
        let rows = FrontPanelDisplayLayout.graphRows
        #expect(rows % 2 == 1)
        #expect(FrontPanelDisplayLayout.row(decibels: 0, rows: rows) == rows / 2)
    }

    /// The gain labels read with their sign, stay inside the graph, and keep clear of each other and of the unit above
    /// them.
    @Test func theGainLabelsKeepClearOfEachOtherAndTheUnit() throws {
        let layout = FrontPanelDisplayLayout.self
        #expect(layout.gainLabel(decibels: 10) == "+10")
        #expect(layout.gainLabel(decibels: 0) == "0")
        #expect(layout.gainLabel(decibels: -5) == "-5")
        let rows = layout.labeledDecibels.map(layout.gainLabelRow(decibels:)).sorted()
        #expect(try #require(rows.first) > DotMatrixFont.glyphRows)
        #expect(try #require(rows.last) + DotMatrixFont.glyphRows <= layout.graphRows)
        for (upper, lower) in zip(rows, rows.dropFirst()) {
            #expect(lower - upper > DotMatrixFont.glyphRows)
        }
    }

    /// On the front panel's display with the status column in, the frequency labels center under their lines, the
    /// lowest one starts where the curve starts, and none touches the next one or the unit at the end.
    @Test func theFrequencyLabelsStandUnderTheirLinesWithoutTouching() throws {
        let layout = FrontPanelDisplayLayout.self
        let curveColumns = layout.curveColumns(graphColumns: layout.graphColumns(displayColumns: Self.frontPanelDisplayColumns))
        let spans = try layout.labeledFrequencies.map { label in
            let column = layout.frequencyLabelColumn(frequencyHz: label.hertz, cells: label.text.count, curveColumns: curveColumns)
            let start = try #require(column)
            return start ..< start + DotMatrixMetrics.columns(forCells: label.text.count)
        }
        #expect(spans.first?.lowerBound == layout.gainScaleColumns)
        let thousand = try #require(layout.column(frequencyHz: 1000, columns: curveColumns))
        let thousandSpan = try #require(spans.first { $0.contains(layout.gainScaleColumns + thousand) })
        #expect(thousandSpan.lowerBound + thousandSpan.count / 2 == layout.gainScaleColumns + thousand)
        let unitStart = layout.gainScaleColumns + curveColumns - DotMatrixMetrics.columns(forCells: layout.frequencyUnit.count)
        for (left, right) in zip(spans, spans.dropFirst() + [unitStart ..< unitStart + 1]) {
            #expect(left.upperBound < right.lowerBound)
        }
    }

    /// The status column slides out by the columns it takes from the curve, in whole dot columns, and the curve takes
    /// the whole display once the column is out.
    @Test func theStatusColumnSlidesOutByTheColumnsItTakesFromTheCurve() {
        let reserved = FrontPanelDisplayLayout.statusReservedColumns
        #expect(FrontPanelDisplayLayout.statusShift(reveal: 1) == 0)
        #expect(FrontPanelDisplayLayout.statusShift(reveal: 0) == reserved)
        #expect(FrontPanelDisplayLayout.statusShift(reveal: 0.5) == Int((Double(reserved) / 2).rounded()))
        #expect(FrontPanelDisplayLayout.statusShift(reveal: .nan) == 0)
        #expect(FrontPanelDisplayLayout.graphColumns(displayColumns: 500, statusShift: reserved) == 500)
        #expect(FrontPanelDisplayLayout.statusColumn(displayColumns: 500, statusShift: reserved) >= 500)
    }
}

private extension FrontPanelDisplayLayoutTests {
    /// The dot columns of the front panel's display: the panel's 1110 points less its padding, the bay's margins, the
    /// frame and the glass's padding leave 954 points.
    static let frontPanelDisplayColumns = 477
}
