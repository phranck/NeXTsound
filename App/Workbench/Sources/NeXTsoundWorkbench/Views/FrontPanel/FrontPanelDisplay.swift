import NeXTsoundCore
import SwiftUI

/// The multifunction display's dot matrix.
///
/// The live EQ curve takes its left part between its gain and frequency scales, with the selected profile's name under
/// it, and the status column on the right shows the SoundBox and the latest message. The grid starts at the display's
/// leading edge, so every dot keeps its whole-pixel position.
///
/// The status column slides in from the right and out to the right in whole dot columns over the unlit grid, and the
/// curve takes the columns it leaves. With reduced motion, it appears and disappears at once.
struct FrontPanelDisplay: View {
    let settings: DSPSettings
    let profileName: String
    let status: FrontPanelStatus
    /// Whether the status column stands in the display.
    let showsStatus: Bool
    @Environment(\.phosphorTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let columns = DotMatrixMetrics.columns(fitting: proxy.size.width)
            ZStack(alignment: .topLeading) {
                DotMatrixGhosts(columns: columns, rows: FrontPanelDisplayLayout.rows, color: theme.ghost)
                    .equatable()
                FrontPanelDisplayDots(
                    settings: settings,
                    profileName: profileName,
                    status: status,
                    theme: theme,
                    columns: columns,
                    statusReveal: showsStatus ? 1 : 0
                )
                .animation(FrontPanelMotion.slide(reduceMotion: reduceMotion), value: showsStatus)
            }
        }
        .frame(height: FrontPanelDisplayLayout.height)
        .accessibilityElement()
        .accessibilityLabel("Analytical high-pass and equalizer response")
        .accessibilityValue(status.spokenDescription(profileName: profileName, showsStatus: showsStatus))
    }
}

/// The lit dots of the multifunction display: the axes, the grid lines and their labels, the curve, the profile's name
/// and the status column.
///
/// An animation of the status column's reveal redraws the dots for every step, and the column moves in whole dot
/// columns. Dots that slide past the display's right edge are cut off.
@Animatable
private struct FrontPanelDisplayDots: View {
    let settings: DSPSettings
    let profileName: String
    let status: FrontPanelStatus
    let theme: PhosphorTheme
    let columns: Int
    /// How far the status column stands in the display, from 0, out of it, to 1, in its place.
    var statusReveal: Double

    var body: some View {
        Canvas { context, size in
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            let statusShift = FrontPanelDisplayLayout.statusShift(reveal: statusReveal)
            let graphColumns = FrontPanelDisplayLayout.graphColumns(displayColumns: columns, statusShift: statusShift)
            let statusColumn = FrontPanelDisplayLayout.statusColumn(displayColumns: columns, statusShift: statusShift)
            var dim = DotMatrixPainter()
            var normal = DotMatrixPainter()
            var bright = DotMatrixPainter()
            paintGrid(into: &dim, columns: graphColumns)
            paintScales(into: &dim, columns: graphColumns)
            paintCurve(into: &bright, columns: graphColumns)
            paintProfileName(into: &bright, columns: graphColumns)
            if statusColumn < columns {
                paintStatus(normal: &normal, bright: &bright, column: statusColumn)
            }
            dim.fill(context, color: theme.dim)
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
    /// Draws the axes along the curve's left and bottom edges, the solid 0 dB line, and dotted lines at the gains and
    /// frequencies the scales label.
    func paintGrid(into painter: inout DotMatrixPainter, columns: Int) {
        let layout = FrontPanelDisplayLayout.self
        let first = layout.gainScaleColumns
        let curveColumns = layout.curveColumns(graphColumns: columns)
        let bottomRow = layout.graphRows - 1
        let zeroRow = layout.row(decibels: 0, rows: layout.graphRows)
        for row in 0 ... bottomRow {
            painter.light(column: first - 1, row: row)
        }
        for column in first ..< first + curveColumns {
            painter.light(column: column, row: bottomRow)
            painter.light(column: column, row: zeroRow)
        }
        for decibels in layout.gridDecibels {
            let row = layout.row(decibels: decibels, rows: layout.graphRows)
            for column in stride(from: first, to: first + curveColumns, by: 2) {
                painter.light(column: column, row: row)
            }
        }
        for frequency in layout.gridFrequenciesHz {
            guard let column = layout.column(frequencyHz: frequency, columns: curveColumns) else {
                continue
            }
            for row in stride(from: 0, to: bottomRow, by: 2) {
                painter.light(column: first + column, row: row)
            }
        }
    }

    /// Labels the gain scale at the curve's left, with its unit at its top, and the frequency scale under the curve,
    /// with its unit at its right end.
    func paintScales(into painter: inout DotMatrixPainter, columns: Int) {
        let layout = FrontPanelDisplayLayout.self
        painter.write(DotMatrixAlignment.trailing.fit(layout.gainUnit, cells: layout.gainLabelCells), column: 0, row: 0)
        for decibels in layout.labeledDecibels {
            let label = DotMatrixAlignment.trailing.fit(layout.gainLabel(decibels: decibels), cells: layout.gainLabelCells)
            painter.write(label, column: 0, row: layout.gainLabelRow(decibels: decibels))
        }
        let curveColumns = layout.curveColumns(graphColumns: columns)
        for label in layout.labeledFrequencies {
            let cells = label.text.count
            guard let column = layout.frequencyLabelColumn(frequencyHz: label.hertz, cells: cells, curveColumns: curveColumns) else {
                continue
            }
            painter.write(label.text, column: column, row: layout.frequencyLabelRow)
        }
        let unitColumns = DotMatrixMetrics.columns(forCells: layout.frequencyUnit.count)
        painter.write(layout.frequencyUnit, column: columns - unitColumns, row: layout.frequencyLabelRow)
    }

    /// Lights each column's row and closes the gap to the previous column's row, so a steep slope stays one line.
    func paintCurve(into painter: inout DotMatrixPainter, columns: Int) {
        let layout = FrontPanelDisplayLayout.self
        guard let samples = try? ResponseCurve.samples(settings: settings, count: layout.curveColumns(graphColumns: columns)) else {
            return
        }
        var previousRow: Int?
        for (index, sample) in samples.enumerated() {
            let row = layout.row(decibels: sample.decibels, rows: layout.graphRows)
            let span = previousRow.map { min($0, row) ... max($0, row) } ?? row ... row
            for filledRow in span {
                painter.light(column: layout.gainScaleColumns + index, row: filledRow)
            }
            previousRow = row
        }
    }

    /// Centers the profile's name under the curve on the display's bottom line.
    func paintProfileName(into painter: inout DotMatrixPainter, columns: Int) {
        let layout = FrontPanelDisplayLayout.self
        let curveColumns = layout.curveColumns(graphColumns: columns)
        let name = DotMatrixAlignment.leading.fit(profileName, cells: DotMatrixMetrics.cells(inColumns: curveColumns))
        let nameColumns = DotMatrixMetrics.columns(forCells: name.count)
        painter.write(name, column: layout.gainScaleColumns + (curveColumns - nameColumns) / 2, row: layout.rows - DotMatrixFont.glyphRows)
    }

    /// Draws the status column from its first dot column: the connection on the first line, each field's label in the
    /// normal tone with its value bright after it, and the message on the bottom line. The message wraps upward with a
    /// hanging indent into the lines the fields leave free.
    func paintStatus(normal: inout DotMatrixPainter, bright: inout DotMatrixPainter, column labelColumn: Int) {
        let layout = FrontPanelDisplayLayout.self
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
