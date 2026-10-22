import NeXTsoundCore
import SwiftUI

/// The geometry of the multifunction display.
///
/// It is as tall as the status column's twelve lines. The EQ curve takes the dot columns that the status column on
/// the right and the gap before it leave, and the selected profile's name sits under the curve.
enum FrontPanelDisplayLayout {
    /// The character cells of the status column.
    static let statusCells = 27
    /// The character cells of the status column's labels.
    static let statusLabelCells = 7
    /// The unlit dot columns between the curve and the status column.
    static let statusGapColumns = 12
    /// The lines of the status column, which set the display's height.
    static let statusLines = 12
    /// The unlit dot rows between the curve and the profile's name.
    static let profileLineGapRows = 2
    /// The display's dot rows.
    static let rows = DotMatrixMetrics.rows(forLines: statusLines)
    /// The curve's dot rows, which leave room for the profile's name under it.
    static let graphRows = rows - DotMatrixFont.glyphRows - profileLineGapRows
    /// The gain the curve shows above and below 0 dB.
    static let decibelRange = 15.0
    /// The frequencies that dotted lines mark across the curve.
    static let gridFrequenciesHz: [Double] = [100, 1000, 10000]
    /// The marker before an error message's first line.
    static let errorMarker = "! "
    /// The marker before every other message's first line.
    static let infoMarker = "> "
    /// The indent of a message's later lines, as wide as its marker.
    static let messageIndent = "  "
}

extension FrontPanelDisplayLayout {
    /// The display's height in points.
    static var height: CGFloat {
        DotMatrixMetrics.size(columns: 1, rows: rows).height
    }

    /// The curve's dot columns on a display of `displayColumns` columns. The curve keeps at least two.
    static func graphColumns(displayColumns: Int) -> Int {
        max(displayColumns - DotMatrixMetrics.columns(forCells: statusCells) - statusGapColumns, 2)
    }

    /// The status column's first dot column on a display of `displayColumns` columns, so the column ends at the
    /// display's right edge.
    static func statusColumn(displayColumns: Int) -> Int {
        displayColumns - DotMatrixMetrics.columns(forCells: statusCells)
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

/// The multifunction display's dot matrix.
///
/// The live EQ curve takes its left part with the selected profile's name under it, and the status column on the
/// right shows the SoundBox and the latest message. The grid starts at the display's leading edge, so every dot keeps
/// its whole-pixel position.
struct FrontPanelDisplay: View {
    let settings: DSPSettings
    let profileName: String
    let status: FrontPanelStatus
    let theme: PhosphorTheme

    var body: some View {
        GeometryReader { proxy in
            let columns = DotMatrixMetrics.columns(fitting: proxy.size.width)
            ZStack(alignment: .topLeading) {
                DotMatrixGhosts(columns: columns, rows: FrontPanelDisplayLayout.rows, color: theme.ghost)
                    .equatable()
                FrontPanelDisplayDots(settings: settings, profileName: profileName, status: status, theme: theme, columns: columns)
            }
        }
        .frame(height: FrontPanelDisplayLayout.height)
        .accessibilityElement()
        .accessibilityLabel("Analytical high-pass and equalizer response")
        .accessibilityValue(spokenDescription)
    }
}

private extension FrontPanelDisplay {
    /// What the display shows, as VoiceOver reads it: the profile, the connection, every field and the message.
    var spokenDescription: String {
        let fields = status.fields.map { "\($0.label) \($0.value)" }
        return ([profileName, status.connection] + fields + [status.message?.text].compactMap(\.self)).joined(separator: ". ")
    }
}

/// The lit dots of the multifunction display: the 0 dB line, the frequency lines, the curve, the profile's name and the
/// status column.
private struct FrontPanelDisplayDots: View {
    let settings: DSPSettings
    let profileName: String
    let status: FrontPanelStatus
    let theme: PhosphorTheme
    let columns: Int

    var body: some View {
        Canvas { context, _ in
            let graphColumns = FrontPanelDisplayLayout.graphColumns(displayColumns: columns)
            var normal = DotMatrixPainter()
            var bright = DotMatrixPainter()
            paintGrid(into: &normal, columns: graphColumns)
            paintCurve(into: &bright, columns: graphColumns)
            paintProfileName(into: &bright, columns: graphColumns)
            paintStatus(normal: &normal, bright: &bright)
            normal.fill(context, color: theme.normal)
            bright.fill(context, color: theme.bright)
        }
        .frame(
            width: DotMatrixMetrics.size(columns: columns, rows: FrontPanelDisplayLayout.rows).width,
            height: FrontPanelDisplayLayout.height
        )
    }
}

private extension FrontPanelDisplayDots {
    func paintGrid(into painter: inout DotMatrixPainter, columns: Int) {
        let rows = FrontPanelDisplayLayout.graphRows
        let zeroRow = FrontPanelDisplayLayout.row(decibels: 0, rows: rows)
        for column in 0 ..< columns {
            painter.light(column: column, row: zeroRow)
        }
        for frequency in FrontPanelDisplayLayout.gridFrequenciesHz {
            guard let column = FrontPanelDisplayLayout.column(frequencyHz: frequency, columns: columns) else {
                continue
            }
            for row in stride(from: 0, to: rows, by: 2) {
                painter.light(column: column, row: row)
            }
        }
    }

    /// Lights each column's row and closes the gap to the previous column's row, so a steep slope stays one line.
    func paintCurve(into painter: inout DotMatrixPainter, columns: Int) {
        guard let samples = try? ResponseCurve.samples(settings: settings, count: columns) else {
            return
        }
        var previousRow: Int?
        for (column, sample) in samples.enumerated() {
            let row = FrontPanelDisplayLayout.row(decibels: sample.decibels, rows: FrontPanelDisplayLayout.graphRows)
            let span = previousRow.map { min($0, row) ... max($0, row) } ?? row ... row
            for filledRow in span {
                painter.light(column: column, row: filledRow)
            }
            previousRow = row
        }
    }

    /// Centers the profile's name under the curve on the display's bottom line.
    func paintProfileName(into painter: inout DotMatrixPainter, columns: Int) {
        let name = DotMatrixAlignment.leading.fit(profileName, cells: DotMatrixMetrics.cells(inColumns: columns))
        let nameColumns = DotMatrixMetrics.columns(forCells: name.count)
        painter.write(name, column: (columns - nameColumns) / 2, row: FrontPanelDisplayLayout.rows - DotMatrixFont.glyphRows)
    }

    /// Draws the status column at the display's right edge: the connection on the first line, each field's label in
    /// the normal tone with its value bright after it, and the message on the bottom line. The message wraps upward
    /// with a hanging indent into the lines the fields leave free.
    func paintStatus(normal: inout DotMatrixPainter, bright: inout DotMatrixPainter) {
        let layout = FrontPanelDisplayLayout.self
        let labelColumn = layout.statusColumn(displayColumns: columns)
        let valueColumn = labelColumn + DotMatrixMetrics.columns(forCells: layout.statusLabelCells) + DotMatrixMetrics.cellSpacing
        let valueCells = layout.statusCells - layout.statusLabelCells
        bright.write(DotMatrixAlignment.leading.fit(status.connection, cells: layout.statusCells), column: labelColumn, row: 0)
        for (index, field) in status.fields.enumerated() {
            let row = (index + 1) * DotMatrixMetrics.linePitch
            normal.write(DotMatrixAlignment.leading.fit(field.label, cells: layout.statusLabelCells), column: labelColumn, row: row)
            bright.write(DotMatrixAlignment.leading.fit(field.value, cells: valueCells), column: valueColumn, row: row)
        }
        guard let message = status.message else {
            return
        }
        let bottomRow = layout.rows - DotMatrixFont.glyphRows
        let room = layout.statusLines - 1 - status.fields.count
        let lines = DotMatrixWrap.lines(
            of: message.text,
            width: layout.statusCells,
            firstPrefix: message.isError ? layout.errorMarker : layout.infoMarker,
            laterPrefix: layout.messageIndent
        ).prefix(room)
        for (index, line) in lines.enumerated() {
            let row = bottomRow - (lines.count - 1 - index) * DotMatrixMetrics.linePitch
            let text = DotMatrixAlignment.leading.fit(line, cells: layout.statusCells)
            if message.tone == .bright {
                bright.write(text, column: labelColumn, row: row)
            } else {
                normal.write(text, column: labelColumn, row: row)
            }
        }
    }
}
