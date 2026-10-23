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
    /// The marker before an error message's first line.
    static let errorMarker = "! "
    /// The marker before every other message's first line.
    static let infoMarker = "> "
    /// The indent of a message's later lines, as wide as its marker.
    static let messageIndent = "  "
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
