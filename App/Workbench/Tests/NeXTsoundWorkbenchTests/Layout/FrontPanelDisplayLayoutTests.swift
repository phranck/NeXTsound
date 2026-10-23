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
