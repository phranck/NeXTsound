import Foundation

/// The front panel's dot-matrix font.
///
/// It resolves a character to its 5×7 pattern the way musiccloud's VFD does, so a letter without a pattern of its
/// own still shows as its base letter instead of a gap.
enum DotMatrixFont {
    /// The dot columns of one glyph.
    static let glyphColumns = 5
    /// The dot rows of one glyph.
    static let glyphRows = 7
}

extension DotMatrixFont {
    /// The pattern of one character.
    ///
    /// Whitespace is an empty cell. Any other character tries itself first, then itself without its combining
    /// marks, then its uppercase form, then that form without marks, and the question mark last.
    ///
    /// - Parameter character: One user-facing character.
    /// - Returns: Seven rows from top to bottom, each holding its five columns in the lowest five bits with the
    ///   leftmost column in the highest of them.
    static func pattern(for character: Character) -> [UInt8] {
        if character.isWhitespace {
            return blankPattern
        }
        for candidate in candidates(for: character) {
            if let pattern = DotMatrixGlyphs.patterns[candidate] {
                return pattern
            }
        }
        return DotMatrixGlyphs.patterns["?"] ?? blankPattern
    }

    /// The lit dots of every dot column of a text, with one empty column between neighboring characters.
    ///
    /// - Parameter text: The text to set.
    /// - Returns: One mask per dot column, where bit 0 is the top row.
    static func columnMasks(for text: String) -> [UInt8] {
        var masks: [UInt8] = []
        for (index, character) in text.enumerated() {
            if index > 0 {
                masks.append(0)
            }
            let rows = pattern(for: character)
            for column in 0 ..< glyphColumns {
                let columnBit = UInt8(1 << (glyphColumns - 1 - column))
                var mask: UInt8 = 0
                for row in 0 ..< glyphRows where rows[row] & columnBit != 0 {
                    mask |= 1 << row
                }
                masks.append(mask)
            }
        }
        return masks
    }
}

private extension DotMatrixFont {
    static let blankPattern = [UInt8](repeating: 0, count: glyphRows)

    /// The characters musiccloud tries for one character, in order, without the ones that are not one character.
    static func candidates(for character: Character) -> [Character] {
        let text = String(character)
        let uppercase = text.uppercased()
        return [text, withoutCombiningMarks(text), uppercase, withoutCombiningMarks(uppercase)].compactMap { candidate in
            candidate.count == 1 ? candidate.first : nil
        }
    }

    /// A text in its canonical decomposition without the combining marks U+0300 to U+036F, so "ǹ" becomes "n".
    static func withoutCombiningMarks(_ text: String) -> String {
        let scalars = text.decomposedStringWithCanonicalMapping.unicodeScalars.filter { scalar in
            !(0x300 ... 0x36F).contains(scalar.value)
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
