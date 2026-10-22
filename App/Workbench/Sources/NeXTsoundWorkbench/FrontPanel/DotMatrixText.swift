import CoreGraphics

/// Where a text sits in its run of character cells.
enum DotMatrixAlignment: Sendable {
    /// Starts at the first cell and is cut off at its end.
    case leading
    /// Ends at the last cell and is cut off at its start, the way a numeric display keeps its last digits.
    case trailing
}

/// A brightness step of a phosphor theme that text and lines are drawn in.
enum DotMatrixTone: Sendable {
    case bright
    case normal
}

/// One line of text on a dot-matrix surface.
struct DotMatrixLine: Equatable, Sendable {
    /// The text, cut to the line's cells where it is longer.
    var text: String
    /// The brightness step of the line.
    var tone: DotMatrixTone = .bright
    /// The cell that shows an underline cursor over whatever character stands in it, if any.
    var cursorCell: Int?
}

/// The layout of a block of text lines inside an empty border.
///
/// The border keeps a readout's rounded corners from clipping a dot, and it reads as one more ring of unlit dots.
struct DotMatrixLinesLayout: Equatable, Sendable {
    /// The character cells of each line.
    var cells: Int
    /// The number of lines.
    var lines = 1
    /// The empty border around the dots, in points.
    var margin: CGFloat = DotMatrixMetrics.pitch
}

extension DotMatrixAlignment {
    /// Fits a text into a number of cells, padding a trailing text with spaces on the left.
    ///
    /// - Parameters:
    ///   - text: The text to fit.
    ///   - cells: The cells available.
    /// - Returns: A leading text cut to `cells` characters, or a trailing text of exactly `cells` characters.
    func fit(_ text: String, cells: Int) -> String {
        let available = max(cells, 0)
        switch self {
        case .leading:
            return String(text.prefix(available))
        case .trailing:
            let tail = String(text.suffix(available))
            return String(repeating: " ", count: available - tail.count) + tail
        }
    }
}

extension DotMatrixLinesLayout {
    /// The dot columns of each line.
    var columns: Int {
        DotMatrixMetrics.columns(forCells: cells)
    }

    /// The dot rows of all lines together.
    var rows: Int {
        DotMatrixMetrics.rows(forLines: lines)
    }

    /// The size of the block, its border included.
    var size: CGSize {
        let grid = DotMatrixMetrics.size(columns: columns, rows: rows)
        return CGSize(width: grid.width + 2 * margin, height: grid.height + 2 * margin)
    }
}

/// Breaks texts into the lines of a dot-matrix surface.
enum DotMatrixWrap {
    /// Breaks a text between words into lines of `width` cells.
    ///
    /// The first line starts with `firstPrefix` and every later one with `laterPrefix`, which gives a message its
    /// marker and its hanging indent. A word longer than a line takes a line of its own and is cut off where it is
    /// drawn.
    static func lines(of text: String, width: Int, firstPrefix: String, laterPrefix: String) -> [String] {
        var lines: [String] = []
        var line = firstPrefix
        var lineHasWord = false
        for word in text.split(whereSeparator: \.isWhitespace) {
            let longer = lineHasWord ? line + " " + word : line + word
            if lineHasWord, longer.count > width {
                lines.append(line)
                line = laterPrefix + word
            } else {
                line = longer
            }
            lineHasWord = true
        }
        lines.append(line)
        return lines
    }
}
