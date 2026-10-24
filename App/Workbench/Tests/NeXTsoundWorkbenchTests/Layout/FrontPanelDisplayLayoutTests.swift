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

    /// The curve lights each column's row and closes the gap to the previous column's, so a steep slope stays one line.
    @Test func aSteepSlopeStaysOneLine() {
        #expect(FrontPanelDisplayLayout.curveSpans(rows: [44, 40, 40, 47]) == [44 ... 44, 40 ... 44, 40 ... 40, 40 ... 47])
    }

    /// The fill lights every row under the curve down to the bottom axis, and none where the curve lies on the axis.
    @Test func theFillReachesDownToTheBottomAxis() {
        let axisRow = FrontPanelDisplayLayout.graphRows - 1
        #expect(FrontPanelDisplayLayout.fillRows(under: 44) == 45 ..< axisRow)
        #expect(FrontPanelDisplayLayout.fillRows(under: axisRow).isEmpty)
        #expect(FrontPanelDisplayLayout.fillRows(under: axisRow + 3).isEmpty)
    }

    /// A band's marker is a round dot centered on the curve at the band's frequency, wherever the curve stands there,
    /// inside its clearance, and as many dots wide as tall.
    @Test func aBandsMarkerCentersOnTheCurveAtItsFrequency() throws {
        let layout = FrontPanelDisplayLayout.self
        let curveColumns = 343
        let bandColumn = try #require(layout.column(frequencyHz: 1000, columns: curveColumns))
        var curveRows = Array(repeating: 20, count: curveColumns)
        curveRows[bandColumn] = 50
        let center = FrontPanelDisplayLayout.Dot(column: layout.gainScaleColumns + bandColumn, row: 50)
        let dots = layout.bandMarkerDots(frequencyHz: 1000, curveRows: curveRows, shape: layout.bandMarkerShape)
        let clearance = layout.bandMarkerDots(frequencyHz: 1000, curveRows: curveRows, shape: layout.bandMarkerClearance)
        let radius = layout.bandMarkerRadius
        #expect(dots.contains(center))
        #expect(dots.count == layout.bandMarkerShape.count)
        #expect(Set(dots).isSubset(of: Set(clearance)))
        #expect(dots.map(\.column).min() == center.column - radius && dots.map(\.column).max() == center.column + radius)
        #expect(dots.map(\.row).min() == center.row - radius && dots.map(\.row).max() == center.row + radius)
        #expect(!dots.contains(FrontPanelDisplayLayout.Dot(column: center.column - radius, row: center.row - radius)))
    }

    /// A band at the edge of the range keeps only the part of its marker that falls on the curve's area, clear of the
    /// left axis and the bottom axis.
    @Test func aBandsMarkerStaysOnTheCurvesArea() {
        let layout = FrontPanelDisplayLayout.self
        let curveRows = Array(repeating: layout.graphRows - 2, count: 343)
        let dots = layout.bandMarkerDots(frequencyHz: 20, curveRows: curveRows, shape: layout.bandMarkerClearance)
        #expect(!dots.isEmpty)
        #expect(dots.allSatisfy { $0.column >= layout.gainScaleColumns && $0.row < layout.graphRows - 1 })
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

    /// A message's card wraps it with its marker and a hanging indent, keeps at most four lines of at most 48 cells,
    /// holds its text inside the padding, and centers on the display.
    @Test func theMessageCardCentersOnTheDisplayAroundItsText() {
        let layout = FrontPanelDisplayLayout.self
        let columns = Self.frontPanelDisplayColumns
        let short = layout.messageCard(FrontPanelMessage(text: "Settings saved"), displayColumns: columns)
        #expect(short.lines == ["> Settings saved"])
        let long = layout.messageCard(
            FrontPanelMessage(text: String(repeating: "word ", count: 80), isError: true),
            displayColumns: columns
        )
        #expect(long.lines.count == layout.messageCardLineLimit)
        #expect(long.lines[0].hasPrefix(layout.errorMarker) && long.lines[1].hasPrefix(layout.messageIndent))
        #expect(long.lines.allSatisfy { $0.count <= layout.messageCardTextCells })
        for card in [short, long] {
            #expect(abs(card.columns.lowerBound - (columns - 1 - card.columns.upperBound)) <= 1)
            #expect(abs(card.rows.lowerBound - (layout.rows - 1 - card.rows.upperBound)) <= 1)
            let lastTextColumn = card.textColumn + DotMatrixMetrics.columns(forCells: card.lines.map(\.count).max() ?? 0) - 1
            let lastTextRow = card.textRow(index: card.lines.count - 1) + DotMatrixFont.glyphRows - 1
            #expect(card.textColumn - card.columns.lowerBound == layout.messageCardPadding + 1)
            #expect(card.columns.upperBound - lastTextColumn == layout.messageCardPadding + 1)
            #expect(card.textRow(index: 0) - card.rows.lowerBound == layout.messageCardPadding + 1)
            #expect(card.rows.upperBound - lastTextRow == layout.messageCardPadding + 1)
            #expect(card.clearedColumns.lowerBound >= 0 && card.clearedColumns.upperBound < columns)
        }
    }

    /// The card's frame leaves out each corner and the dot beside it on either edge, and joins the edges with a dot on
    /// the diagonal, so its corners read as rounded.
    @Test func theMessageCardsFrameRoundsItsCorners() {
        typealias Dot = FrontPanelDisplayLayout.Dot
        let card = FrontPanelDisplayLayout.messageCard(
            FrontPanelMessage(text: "Settings saved"),
            displayColumns: Self.frontPanelDisplayColumns
        )
        let frame = Set(card.frameDots)
        let left = card.columns.lowerBound
        let bottom = card.rows.upperBound
        #expect(frame.count == card.frameDots.count)
        #expect(frame.allSatisfy { card.columns.contains($0.column) && card.rows.contains($0.row) })
        #expect(![Dot(column: left, row: bottom), Dot(column: left + 1, row: bottom), Dot(column: left, row: bottom - 1)]
            .contains(where: frame.contains))
        #expect([Dot(column: left + 1, row: bottom - 1), Dot(column: left + 2, row: bottom), Dot(column: left, row: bottom - 2)]
            .allSatisfy(frame.contains))
    }
}

private extension FrontPanelDisplayLayoutTests {
    /// The dot columns of the front panel's display: the panel's 1110 points less its padding, the bay's margins, the
    /// frame and the glass's padding leave 954 points.
    static let frontPanelDisplayColumns = 477
}
