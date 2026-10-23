import CoreGraphics

/// The geometry every dot-matrix surface of the front panel shares.
///
/// A dot is 1.5 pt with a 0.5 pt gap, so on a Retina display both fall on whole device pixels, three and one, and
/// every dot stays sharp. Text sits in cells of five dot columns with one empty column between cells, and lines of
/// text are two empty dot rows apart.
enum DotMatrixMetrics {
    /// The width and height of one dot.
    static let dotSize: CGFloat = 1.5
    /// The space between two neighboring dots.
    static let dotGap: CGFloat = 0.5
    /// The distance from one dot to the next.
    static let pitch: CGFloat = dotSize + dotGap
    /// The empty dot columns between two character cells.
    static let cellSpacing = 1
    /// The empty dot rows between two lines of text.
    static let lineSpacing = 2
    /// The dot rows from the top of one line of text to the top of the next.
    static let linePitch = DotMatrixFont.glyphRows + lineSpacing
}

extension DotMatrixMetrics {
    /// The dot columns that a run of character cells takes.
    static func columns(forCells cells: Int) -> Int {
        max(cells * (DotMatrixFont.glyphColumns + cellSpacing) - cellSpacing, 0)
    }

    /// The character cells that fit into a run of dot columns.
    static func cells(inColumns columns: Int) -> Int {
        max((columns + cellSpacing) / (DotMatrixFont.glyphColumns + cellSpacing), 0)
    }

    /// The dot rows that a number of text lines takes.
    static func rows(forLines lines: Int) -> Int {
        max(lines * linePitch - lineSpacing, 0)
    }

    /// The dot columns that fit into a width.
    static func columns(fitting width: CGFloat) -> Int {
        max(Int(((width + dotGap) / pitch).rounded(.down)), 0)
    }

    /// The size of a grid of dots, from the outer edge of its first dot to the outer edge of its last.
    static func size(columns: Int, rows: Int) -> CGSize {
        CGSize(width: max(CGFloat(columns) * pitch - dotGap, 0), height: max(CGFloat(rows) * pitch - dotGap, 0))
    }

    /// The rectangle of one dot, with the grid's first dot at the origin.
    static func rect(column: Int, row: Int) -> CGRect {
        CGRect(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch, width: dotSize, height: dotSize)
    }
}
