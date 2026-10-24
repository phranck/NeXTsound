import SwiftUI

/// Collects the lit dots of one color and fills them in one pass.
struct DotMatrixPainter {
    private(set) var path = Path()
}

extension DotMatrixPainter {
    /// Lights one dot.
    mutating func light(column: Int, row: Int) {
        path.addRect(DotMatrixMetrics.rect(column: column, row: row))
    }

    /// Lights the dots of a text, starting at a dot column and row.
    mutating func write(_ text: String, column: Int, row: Int) {
        for (offset, mask) in DotMatrixFont.columnMasks(for: text).enumerated() where mask != 0 {
            for bit in 0 ..< DotMatrixFont.glyphRows where mask & (1 << bit) != 0 {
                light(column: column + offset, row: row + bit)
            }
        }
    }

    /// Lights an underline cursor in one character cell of a line that starts at a dot row.
    mutating func cursor(cell: Int, row: Int) {
        let firstColumn = cell * (DotMatrixFont.glyphColumns + DotMatrixMetrics.cellSpacing)
        for column in firstColumn ..< firstColumn + DotMatrixFont.glyphColumns {
            light(column: column, row: row + DotMatrixFont.glyphRows - 1)
        }
    }

    /// Fills every collected dot.
    func fill(_ context: GraphicsContext, color: Color) {
        context.fill(path, with: .color(color))
    }

    /// Fills every collected dot with a shading, such as a gradient that runs across all of them.
    func fill(_ context: GraphicsContext, shading: GraphicsContext.Shading) {
        context.fill(path, with: shading)
    }
}

/// The unlit dots of a grid.
///
/// They change only with the grid's size and color, so they redraw apart from the lit dots in front of them.
struct DotMatrixGhosts: View, Equatable {
    let columns: Int
    let rows: Int
    let color: Color

    var body: some View {
        Canvas { context, _ in
            var painter = DotMatrixPainter()
            for row in 0 ..< rows {
                for column in 0 ..< columns {
                    painter.light(column: column, row: row)
                }
            }
            painter.fill(context, color: color)
        }
        .frame(width: gridSize.width, height: gridSize.height)
    }
}

private extension DotMatrixGhosts {
    var gridSize: CGSize {
        DotMatrixMetrics.size(columns: columns, rows: rows)
    }
}

/// Lines of text on a dot-matrix surface, over its unlit dots and inside its empty border.
struct DotMatrixLinesView: View {
    let lines: [DotMatrixLine]
    let layout: DotMatrixLinesLayout
    var alignment: DotMatrixAlignment = .leading
    @Environment(\.phosphorTheme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            DotMatrixGhosts(columns: layout.columns, rows: layout.rows, color: theme.ghost)
                .equatable()
            Canvas { context, _ in
                for tone in [DotMatrixTone.normal, .bright] {
                    var painter = DotMatrixPainter()
                    for (index, line) in lines.enumerated() where line.tone == tone {
                        let row = index * DotMatrixMetrics.linePitch
                        painter.write(alignment.fit(line.text, cells: layout.cells), column: 0, row: row)
                        if let cell = line.cursorCell {
                            painter.cursor(cell: cell, row: row)
                        }
                    }
                    painter.fill(context, color: theme.color(for: tone))
                }
            }
        }
        .frame(width: layout.size.width - 2 * layout.margin, height: layout.size.height - 2 * layout.margin)
        .padding(layout.margin)
    }
}
