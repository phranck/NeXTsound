import CoreGraphics
import NeXTsoundCore

/// The geometry of the multifunction display.
///
/// It is as tall as the status column's twelve lines. The graph takes the dot columns that the status column on the
/// right and the gap before it leave: the gain scale at its left, and the EQ curve between an axis along its left edge
/// and one along its bottom edge. The frequency scale stands under the curve, and the selected profile's name under
/// that.
enum FrontPanelDisplayLayout {
    /// The character cells of the status column.
    static let statusCells = 26
    /// The character cells of the status column's labels.
    static let statusLabelCells = 7
    /// The unlit dot columns between the curve and the status column.
    static let statusGapColumns = 12
    /// The lines of the status column, which set the display's height.
    static let statusLines = 12
    /// The unlit dot rows between the frequency labels and the profile's name.
    static let profileLineGapRows = 2
    /// The unlit dot row between the curve's bottom axis and the frequency labels.
    static let frequencyLabelGapRows = 1
    /// The display's dot rows.
    static let rows = DotMatrixMetrics.rows(forLines: statusLines)
    /// The curve's dot rows, its bottom axis included, which leave room for the frequency labels and the profile's
    /// name under it. Their count is odd, so 0 dB falls on the middle row.
    static let graphRows = rows - DotMatrixFont.glyphRows - profileLineGapRows - DotMatrixFont.glyphRows - frequencyLabelGapRows
    /// The first dot row of the frequency labels.
    static let frequencyLabelRow = graphRows + frequencyLabelGapRows
    /// The gain the curve shows above and below 0 dB.
    static let decibelRange = 15.0
    /// The frequencies that dotted lines mark across the curve.
    static let gridFrequenciesHz: [Double] = [100, 1000, 10000]
    /// The gains that dotted lines mark across the curve, besides the solid line at 0 dB.
    static let gridDecibels: [Double] = [10, 5, -5, -10]
    /// The gains the scale at the curve's left labels.
    static let labeledDecibels: [Double] = [10, 5, 0, -5, -10]
    /// The frequencies the scale under the curve labels: the curve's lowest one and the decades its lines mark.
    static let labeledFrequencies: [(hertz: Double, text: String)] = [(20, "20"), (100, "100"), (1000, "1k"), (10000, "10k")]
    /// The unit at the top of the gain scale.
    static let gainUnit = "dB"
    /// The unit at the right end of the frequency scale.
    static let frequencyUnit = "Hz"
    /// The character cells of a gain label, as wide as the widest of them.
    static let gainLabelCells = 3
    /// The dot columns the gain scale takes at the curve's left: its labels, an unlit column and the left axis.
    static let gainScaleColumns = DotMatrixMetrics.columns(forCells: gainLabelCells) + 2
    /// How far a band marker reaches from the dot its band's frequency and gain fall on.
    static let bandMarkerRadius = 2
    /// A band marker's dots around the dot its band's frequency and gain fall on.
    static let bandMarkerShape = roundDot(radius: bandMarkerRadius)
    /// The dots the curve, its fill and the grid leave unlit around the dot a band's frequency and gain fall on: the
    /// marker and an unlit edge one dot wide, so the marker stands clear of them.
    static let bandMarkerClearance = roundDot(radius: bandMarkerRadius + 1)
    /// The marker before an error message's first line.
    static let errorMarker = "! "
    /// The marker before every other message's first line.
    static let infoMarker = "> "
    /// The indent of a message's later lines, as wide as its marker.
    static let messageIndent = "  "
    /// The most character cells a line of the message card holds.
    static let messageCardTextCells = 48
    /// The most lines a message takes in its card.
    static let messageCardLineLimit = 4
    /// The unlit dot columns between the message card's side edges and its text.
    static let messageCardPaddingColumns = 3
    /// The unlit dot rows between the message card's top and bottom edges and its text.
    static let messageCardPaddingRows = 2
    /// The dot columns that the status column takes from the curve, the gap before it included. The column slides
    /// this far to the right to leave the display.
    static let statusReservedColumns = DotMatrixMetrics.columns(forCells: statusCells) + statusGapColumns
}

extension FrontPanelDisplayLayout {
    /// The display's height in points.
    static var height: CGFloat {
        DotMatrixMetrics.size(columns: 1, rows: rows).height
    }

    /// The graph's dot columns, its gain scale included, on a display of `displayColumns` columns while the status
    /// column stands `statusShift` dot columns to the right of its place, so the graph ends where the gap before the
    /// column begins. The graph keeps at least two.
    static func graphColumns(displayColumns: Int, statusShift: Int = 0) -> Int {
        max(displayColumns - statusReservedColumns + statusShift, 2)
    }

    /// The curve's dot columns on a graph of `graphColumns` columns, right of the gain scale. The curve keeps at least
    /// two.
    static func curveColumns(graphColumns: Int) -> Int {
        max(graphColumns - gainScaleColumns, 2)
    }

    /// The rows the curve lights in each of its columns, from the row each column's gain falls on: that row and the
    /// rows that close the gap to the previous column's, so a steep slope stays one line.
    static func curveSpans(rows: [Int]) -> [ClosedRange<Int>] {
        var spans: [ClosedRange<Int>] = []
        var previousRow: Int?
        for row in rows {
            spans.append(previousRow.map { min($0, row) ... max($0, row) } ?? row ... row)
            previousRow = row
        }
        return spans
    }

    /// The rows the fill lights in a curve column whose lowest lit row is `lowestRow`: every row down to the bottom
    /// axis, which stays clear, and none where the curve already lies on the axis.
    static func fillRows(under lowestRow: Int) -> Range<Int> {
        let axisRow = graphRows - 1
        return min(lowestRow + 1, axisRow) ..< axisRow
    }

    /// The offsets of a round dot of `radius` dots: a filled square as wide as twice the radius and one, without its
    /// four corners.
    static func roundDot(radius: Int) -> [Dot] {
        (-radius ... radius).flatMap { row in
            (-radius ... radius).compactMap { column in
                abs(row) == radius && abs(column) == radius ? nil : Dot(column: column, row: row)
            }
        }
    }

    /// The dots of `shape` around a band at `frequencyHz` on the curve whose row in each column `curveRows` holds, in
    /// the display's dot columns and rows. The shape centers on the curve's row at the band's column, so the marker
    /// lies on the curve wherever the other bands or the high-pass shape it. Dots that would fall left or right of the
    /// curve or on its bottom axis are left out, so a band at the edge of the range shows the part of its marker that
    /// fits.
    static func bandMarkerDots(frequencyHz: Double, curveRows: [Int], shape: [Dot]) -> [Dot] {
        guard
            let center = column(frequencyHz: frequencyHz, columns: curveRows.count),
            curveRows.indices.contains(center)
        else {
            return []
        }
        let centerRow = curveRows[center]
        return shape.compactMap { offset in
            let column = center + offset.column
            let row = centerRow + offset.row
            guard
                curveRows.indices.contains(column),
                (0 ..< graphRows - 1).contains(row)
            else {
                return nil
            }
            return Dot(column: gainScaleColumns + column, row: row)
        }
    }

    /// A gain's label: the gain in whole decibels with its sign, and 0 without one.
    static func gainLabel(decibels: Double) -> String {
        decibels > 0 ? "+\(Int(decibels))" : "\(Int(decibels))"
    }

    /// The first dot row of a gain's label, which centers the label on the row of its gain.
    static func gainLabelRow(decibels: Double) -> Int {
        row(decibels: decibels, rows: graphRows) - DotMatrixFont.glyphRows / 2
    }

    /// The first dot column of a frequency label of `cells` cells: centered under its frequency's column, and kept
    /// within the curve's `curveColumns` columns, so the label of the lowest frequency starts where the curve starts.
    static func frequencyLabelColumn(frequencyHz: Double, cells: Int, curveColumns: Int) -> Int? {
        guard let center = column(frequencyHz: frequencyHz, columns: curveColumns) else {
            return nil
        }
        let width = DotMatrixMetrics.columns(forCells: cells)
        return gainScaleColumns + min(max(center - width / 2, 0), max(curveColumns - width, 0))
    }

    /// The status column's first dot column on a display of `displayColumns` columns: where the column ends at the
    /// display's right edge, and `statusShift` dot columns to the right of that.
    static func statusColumn(displayColumns: Int, statusShift: Int = 0) -> Int {
        displayColumns - DotMatrixMetrics.columns(forCells: statusCells) + statusShift
    }

    /// How far the status column stands to the right of its place, in whole dot columns, for a reveal from 0, out of
    /// the display, to 1, in its place. Whole columns keep every lit dot on the grid while the column slides.
    static func statusShift(reveal: Double) -> Int {
        let clamped = reveal.isFinite ? min(max(reveal, 0), 1) : 1
        return Int(((1 - clamped) * Double(statusReservedColumns)).rounded())
    }

    /// The card that shows `message` on a display of `displayColumns` columns. Its lines break between words, with the
    /// marker before the first line and a hanging indent after it, at most `messageCardTextCells` cells wide or as many
    /// as the display leaves, and at most `messageCardLineLimit` of them, so a longer message keeps its first lines. The
    /// card is as wide as its longest line with the padding and the frame around it, and centers on the display.
    static func messageCard(_ message: FrontPanelMessage, displayColumns: Int) -> MessageCard {
        // The padding, the frame and the unlit ring around it on either side of the text.
        let edgeColumns = 2 * (messageCardPaddingColumns + 2)
        let cells = min(messageCardTextCells, DotMatrixMetrics.cells(inColumns: displayColumns - edgeColumns))
        let lines = DotMatrixWrap.lines(
            of: message.text,
            width: max(cells, 1),
            firstPrefix: message.isError ? errorMarker : infoMarker,
            laterPrefix: messageIndent
        ).prefix(messageCardLineLimit)
        let width = DotMatrixMetrics.columns(forCells: lines.map(\.count).max() ?? 0) + 2 * (messageCardPaddingColumns + 1)
        let height = DotMatrixMetrics.rows(forLines: lines.count) + 2 * (messageCardPaddingRows + 1)
        let firstColumn = (displayColumns - width) / 2
        let firstRow = (rows - height) / 2
        return MessageCard(lines: Array(lines), columns: firstColumn ... firstColumn + width - 1, rows: firstRow ... firstRow + height - 1)
    }

    /// The dot row a gain falls on among `rows` rows, with 0 dB in the middle row and every gain beyond the range on
    /// an edge row.
    static func row(decibels: Double, rows: Int) -> Int {
        let clamped = decibels.isFinite ? min(max(decibels, -decibelRange), decibelRange) : 0
        return Int(((decibelRange - clamped) / (2 * decibelRange) * Double(rows - 1)).rounded())
    }

    /// The dot column a frequency falls on among `columns` columns.
    ///
    /// It uses the band frequency's logarithmic scale, the one `ResponseCurve.samples(settings:count:)` samples, so a
    /// grid line and the curve agree on where a frequency is.
    static func column(frequencyHz: Double, columns: Int) -> Int? {
        guard let scale = try? LogarithmicScale(bounds: DSPParameter.bandFrequency.bounds) else {
            return nil
        }
        return Int((scale.position(for: Float(frequencyHz)) * Double(columns - 1)).rounded())
    }
}

extension FrontPanelDisplayLayout {
    /// A dot of the display, by its dot column and dot row, or an offset from another dot.
    struct Dot: Hashable {
        let column: Int
        let row: Int
    }

    /// The card a message shows in, over the middle of the display: a frame with rounded corners around the message's
    /// lines, and a ring of unlit dots around the frame that sets the card apart from the curve and the status column.
    struct MessageCard {
        /// The dots each edge of the frame leaves out toward a corner. A dot on the corner's diagonal joins the two
        /// edges, so the corner reads as rounded.
        static let cornerInset = 2

        /// The message's lines, the first with its marker.
        let lines: [String]
        /// The dot columns the frame spans, its side edges included.
        let columns: ClosedRange<Int>
        /// The dot rows the frame spans, its top and bottom edges included.
        let rows: ClosedRange<Int>
    }
}

extension FrontPanelDisplayLayout.MessageCard {
    /// The first dot column of the card's text, inside the frame and its padding.
    var textColumn: Int {
        columns.lowerBound + 1 + FrontPanelDisplayLayout.messageCardPaddingColumns
    }

    /// The dot columns the card keeps unlit beneath it: its frame and one unlit column on either side.
    var clearedColumns: ClosedRange<Int> {
        columns.lowerBound - 1 ... columns.upperBound + 1
    }

    /// The dot rows the card keeps unlit beneath it: its frame and one unlit row above and below it.
    var clearedRows: ClosedRange<Int> {
        rows.lowerBound - 1 ... rows.upperBound + 1
    }

    /// The frame's dots: its four edges, each stopping `cornerInset` dots short of a corner, and the dot on each
    /// corner's diagonal that joins two of them.
    var frameDots: [FrontPanelDisplayLayout.Dot] {
        typealias Dot = FrontPanelDisplayLayout.Dot
        let inset = Self.cornerInset
        let left = columns.lowerBound
        let right = columns.upperBound
        let top = rows.lowerBound
        let bottom = rows.upperBound
        let horizontal = (left + inset ... right - inset).flatMap { column in
            [Dot(column: column, row: top), Dot(column: column, row: bottom)]
        }
        let vertical = (top + inset ... bottom - inset).flatMap { row in
            [Dot(column: left, row: row), Dot(column: right, row: row)]
        }
        let diagonal = inset - 1
        let corners = [
            Dot(column: left + diagonal, row: top + diagonal),
            Dot(column: right - diagonal, row: top + diagonal),
            Dot(column: left + diagonal, row: bottom - diagonal),
            Dot(column: right - diagonal, row: bottom - diagonal),
        ]
        return horizontal + vertical + corners
    }

    /// The first dot row of the line at `index`, inside the frame and its padding.
    func textRow(index: Int) -> Int {
        rows.lowerBound + 1 + FrontPanelDisplayLayout.messageCardPaddingRows + index * DotMatrixMetrics.linePitch
    }
}
