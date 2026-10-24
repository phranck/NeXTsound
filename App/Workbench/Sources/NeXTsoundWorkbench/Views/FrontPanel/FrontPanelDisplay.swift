import NeXTsoundCore
import SwiftUI

/// The multifunction display's dot matrix.
///
/// The live EQ curve takes its left part between its gain and frequency scales, with the selected profile's name under
/// it, and the status column on the right shows the SoundBox. A message stands in an overlay over the display's bottom
/// lines, across its whole width. The grid starts at the display's leading edge, so every dot keeps its whole-pixel
/// position.
///
/// The status column slides in from the right and out to the right in whole dot columns over the unlit grid, and the
/// curve takes the columns it leaves. With reduced motion, it appears and disappears at once.
struct FrontPanelDisplay: View {
    let settings: DSPSettings
    let profileName: String
    let status: FrontPanelStatus
    /// Whether the status column stands in the display.
    let showsStatus: Bool
    /// The band the band keys select, whose marker lights in the peak step.
    var selectedBand: Int?
    /// The message the overlay shows, or nil while it shows none.
    var overlayMessage: FrontPanelMessage?
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
                    selectedBand: selectedBand,
                    overlayMessage: overlayMessage,
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

/// The lit dots of the multifunction display: the axes, the grid lines and their labels, the curve with its fill, the
/// band markers, the profile's name, the status column, and over them the message overlay.
///
/// An animation of the status column's reveal redraws the dots for every step, and the column moves in whole dot
/// columns. Dots that slide past the display's right edge are cut off. The overlay leaves every other dot under it
/// unlit, so only the unlit grid stands around its text.
@Animatable
private struct FrontPanelDisplayDots: View {
    let settings: DSPSettings
    let profileName: String
    let status: FrontPanelStatus
    let theme: PhosphorTheme
    let selectedBand: Int?
    let overlayMessage: FrontPanelMessage?
    let columns: Int
    /// How far the status column stands in the display, from 0, out of it, to 1, in its place.
    var statusReveal: Double

    var body: some View {
        Canvas { context, size in
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            let statusShift = FrontPanelDisplayLayout.statusShift(reveal: statusReveal)
            let graphColumns = FrontPanelDisplayLayout.graphColumns(displayColumns: columns, statusShift: statusShift)
            let statusColumn = FrontPanelDisplayLayout.statusColumn(displayColumns: columns, statusShift: statusShift)
            var fill = DotMatrixPainter()
            var dim = DotMatrixPainter()
            var normal = DotMatrixPainter()
            var bright = DotMatrixPainter()
            var peak = DotMatrixPainter()
            let curveRows = curveRows(columns: graphColumns)
            let markers = bandMarkers(curveRows: curveRows)
            let cleared = Set(markers.flatMap(\.clearance))
            paintGrid(into: &dim, columns: graphColumns, sparing: cleared)
            paintScales(into: &dim, columns: graphColumns)
            paintCurve(into: &bright, fill: &fill, rows: curveRows, sparing: cleared)
            paintBandMarkers(markers, dim: &dim, peak: &peak)
            paintProfileName(into: &bright, columns: graphColumns)
            if statusColumn < columns {
                paintStatus(normal: &normal, bright: &bright, column: statusColumn)
            }
            var underlay = context
            let overlayLines = overlayMessage.map { FrontPanelDisplayLayout.messageOverlayLines($0, displayColumns: columns) } ?? []
            if !overlayLines.isEmpty {
                underlay.clip(to: Path(overlayArea(lineCount: overlayLines.count, size: size)), options: .inverse)
            }
            fill.fill(underlay, shading: fillShading)
            dim.fill(underlay, color: theme.dim)
            normal.fill(underlay, color: theme.normal)
            bright.fill(underlay, color: theme.bright)
            peak.fill(underlay, color: theme.peak)
            if let overlayMessage, !overlayLines.isEmpty {
                paintOverlay(overlayLines, tone: overlayMessage.tone, in: context)
            }
        }
        .frame(
            width: DotMatrixMetrics.size(columns: columns, rows: FrontPanelDisplayLayout.rows).width,
            height: FrontPanelDisplayLayout.height
        )
    }
}

/// A band's marker on the curve: its dots, the dots it keeps clear of the curve, its fill and the grid, and whether the
/// band keys select its band.
private struct BandMarker {
    let dots: [FrontPanelDisplayLayout.Dot]
    let clearance: [FrontPanelDisplayLayout.Dot]
    let isSelected: Bool
}

private extension FrontPanelDisplayDots {
    /// The fill's opacity at the graph's top.
    static let fillTopOpacity = 0.55
    /// The fill's opacity at the graph's bottom axis.
    static let fillBottomOpacity = 0.05

    /// Draws the axes along the curve's left and bottom edges, the solid 0 dB line, and dotted lines at the gains and
    /// frequencies the scales label. The lines leave out the dots in `sparing`, which the band markers clear.
    func paintGrid(into painter: inout DotMatrixPainter, columns: Int, sparing: Set<FrontPanelDisplayLayout.Dot>) {
        let layout = FrontPanelDisplayLayout.self
        let first = layout.gainScaleColumns
        let curveColumns = layout.curveColumns(graphColumns: columns)
        let bottomRow = layout.graphRows - 1
        let zeroRow = layout.row(decibels: 0, rows: layout.graphRows)
        func light(column: Int, row: Int) {
            if !sparing.contains(FrontPanelDisplayLayout.Dot(column: column, row: row)) {
                painter.light(column: column, row: row)
            }
        }
        for row in 0 ... bottomRow {
            light(column: first - 1, row: row)
        }
        for column in first ..< first + curveColumns {
            light(column: column, row: bottomRow)
            light(column: column, row: zeroRow)
        }
        for decibels in layout.gridDecibels {
            let row = layout.row(decibels: decibels, rows: layout.graphRows)
            for column in stride(from: first, to: first + curveColumns, by: 2) {
                light(column: column, row: row)
            }
        }
        for frequency in layout.gridFrequenciesHz {
            guard let column = layout.column(frequencyHz: frequency, columns: curveColumns) else {
                continue
            }
            for row in stride(from: 0, to: bottomRow, by: 2) {
                light(column: first + column, row: row)
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

    /// Lights the curve's dots and, under each of its columns, the dots of the fill down to the bottom axis. Both leave
    /// out the dots in `sparing`, which the band markers clear, so each marker stands on its own unlit edge.
    func paintCurve(
        into painter: inout DotMatrixPainter,
        fill: inout DotMatrixPainter,
        rows: [Int],
        sparing: Set<FrontPanelDisplayLayout.Dot>
    ) {
        let layout = FrontPanelDisplayLayout.self
        for (index, span) in layout.curveSpans(rows: rows).enumerated() {
            let column = layout.gainScaleColumns + index
            for row in span where !sparing.contains(FrontPanelDisplayLayout.Dot(column: column, row: row)) {
                painter.light(column: column, row: row)
            }
            for row in layout.fillRows(under: span.upperBound) where !sparing.contains(FrontPanelDisplayLayout.Dot(
                column: column,
                row: row
            )) {
                fill.light(column: column, row: row)
            }
        }
    }

    /// The marker of each enabled band, on the curve at the band's frequency. A disabled band shapes no part of the
    /// curve, so it has no marker.
    func bandMarkers(curveRows: [Int]) -> [BandMarker] {
        let layout = FrontPanelDisplayLayout.self
        return settings.bands.enumerated().compactMap { index, band in
            guard band.isEnabled else {
                return nil
            }
            let frequency = Double(band.frequencyHz)
            return BandMarker(
                dots: layout.bandMarkerDots(frequencyHz: frequency, curveRows: curveRows, shape: layout.bandMarkerShape),
                clearance: layout.bandMarkerDots(frequencyHz: frequency, curveRows: curveRows, shape: layout.bandMarkerClearance),
                isSelected: index == selectedBand
            )
        }
    }

    /// The row the curve lights in each of its columns on a graph of `columns` columns, which is empty where the
    /// response cannot be computed.
    func curveRows(columns: Int) -> [Int] {
        let layout = FrontPanelDisplayLayout.self
        guard let samples = try? ResponseCurve.samples(settings: settings, count: layout.curveColumns(graphColumns: columns)) else {
            return []
        }
        return samples.map { layout.row(decibels: $0.decibels, rows: layout.graphRows) }
    }

    /// Lights the band markers: the selected band's in the peak step, above the curve's bright step, and the others in
    /// the dim step, so the selected one stands out in every display color.
    func paintBandMarkers(_ markers: [BandMarker], dim: inout DotMatrixPainter, peak: inout DotMatrixPainter) {
        for marker in markers {
            for dot in marker.dots {
                if marker.isSelected {
                    peak.light(column: dot.column, row: dot.row)
                } else {
                    dim.light(column: dot.column, row: dot.row)
                }
            }
        }
    }

    /// The fill's gradient in the curve's color, strongest at the graph's top and fading out toward its bottom axis,
    /// so the area under a raised band glows brightest.
    var fillShading: GraphicsContext.Shading {
        let height = DotMatrixMetrics.size(columns: 1, rows: FrontPanelDisplayLayout.graphRows).height
        return .linearGradient(
            Gradient(colors: [theme.bright.opacity(Self.fillTopOpacity), theme.bright.opacity(Self.fillBottomOpacity)]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: height)
        )
    }

    /// Centers the profile's name under the curve on the display's bottom line.
    func paintProfileName(into painter: inout DotMatrixPainter, columns: Int) {
        let layout = FrontPanelDisplayLayout.self
        let curveColumns = layout.curveColumns(graphColumns: columns)
        let name = DotMatrixAlignment.leading.fit(profileName, cells: DotMatrixMetrics.cells(inColumns: curveColumns))
        let nameColumns = DotMatrixMetrics.columns(forCells: name.count)
        painter.write(name, column: layout.gainScaleColumns + (curveColumns - nameColumns) / 2, row: layout.rows - DotMatrixFont.glyphRows)
    }

    /// Draws the status column from its first dot column: the connection on the first line, and each field's label in
    /// the normal tone with its value bright after it on the lines below, as many as the column has.
    func paintStatus(normal: inout DotMatrixPainter, bright: inout DotMatrixPainter, column labelColumn: Int) {
        let layout = FrontPanelDisplayLayout.self
        let valueColumn = labelColumn + DotMatrixMetrics.columns(forCells: layout.statusLabelCells) + DotMatrixMetrics.cellSpacing
        let valueCells = layout.statusCells - layout.statusLabelCells
        bright.write(DotMatrixAlignment.leading.fit(status.connection, cells: layout.statusCells), column: labelColumn, row: 0)
        for (index, field) in status.fields.prefix(layout.statusLines - 1).enumerated() {
            let row = (index + 1) * DotMatrixMetrics.linePitch
            normal.write(DotMatrixAlignment.leading.fit(field.label, cells: layout.statusLabelCells), column: labelColumn, row: row)
            bright.write(DotMatrixAlignment.leading.fit(field.value, cells: valueCells), column: valueColumn, row: row)
        }
    }

    /// The part of the display the overlay keeps to itself: from the unlit row above its frame line down to the
    /// display's bottom edge, across its whole width.
    func overlayArea(lineCount: Int, size: CGSize) -> CGRect {
        let top = DotMatrixMetrics.rect(column: 0, row: FrontPanelDisplayLayout.messageOverlayTopRow(lineCount: lineCount)).minY
        return CGRect(x: 0, y: top, width: size.width, height: size.height - top)
    }

    /// Draws the overlay: a frame line across the display in the dim step, and the message's lines under it in the
    /// message's own tone, the last one on the display's bottom line.
    func paintOverlay(_ lines: [String], tone: DotMatrixTone, in context: GraphicsContext) {
        let layout = FrontPanelDisplayLayout.self
        var frame = DotMatrixPainter()
        var text = DotMatrixPainter()
        let frameRow = layout.messageOverlayFrameRow(lineCount: lines.count)
        for column in 0 ..< columns {
            frame.light(column: column, row: frameRow)
        }
        for (index, line) in lines.enumerated() {
            text.write(line, column: 0, row: layout.messageOverlayTextRow(index: index, lineCount: lines.count))
        }
        frame.fill(context, color: theme.dim)
        text.fill(context, color: tone == .bright ? theme.bright : theme.normal)
    }
}
