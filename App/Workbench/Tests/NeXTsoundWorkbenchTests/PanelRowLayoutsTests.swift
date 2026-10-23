import SwiftUI
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct SharedWidthRowTests {
    /// Views with a share of two thirds take two thirds of the widest whole-share view's width, even where their
    /// content asks for more, so two of them and a view 120 points wide at 10 points' spacing are 2 × 80 + 120 + 20
    /// points wide.
    @Test func aPartialShareTakesItsPartOfTheWholeViewsWidth() throws {
        let row = SharedWidthRow(spacing: 10) {
            Color.clear.frame(width: 90, height: 10).rowWidthShare(2 / 3)
            Color.clear.frame(width: 60, height: 10).rowWidthShare(2 / 3)
            Color.clear.frame(width: 120, height: 10)
        }
        let image = try #require(ImageRenderer(content: row).cgImage)
        #expect(image.width == 300)
    }
}

@MainActor
struct IndicatorKeyRowTests {
    /// The capitals of the indicator's caption start at the row's top, where the key's top is, so the caption's ink
    /// reaches the first row of device pixels. The row stays as tall as its key, 40 points, although the caption
    /// reaches above it by the space it keeps over its capitals.
    @Test func theCaptionsCapitalsStartLevelWithTheKeysTop() throws {
        _ = FrontPanelFonts.registration
        let row = IndicatorKeyRow(minimumSpacing: 12) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 8, height: 8)
                ControlCaption(wrappingToWidestWord: "Safety unverified", alignment: .leading)
            }
            Color.clear.frame(width: 40, height: 40)
        }
        .frame(width: 160)
        let pixels = try RenderedPixels(row)
        #expect(pixels.height == 80)
        #expect(try #require(pixels.firstRowWithInk) <= 1)
    }
}

private extension RenderedPixels {
    /// The brightness above which a pixel counts as ink. A caption's pixel passes it where its glyph covers more than
    /// two fifths of the pixel.
    static let inkThreshold = 64

    /// The first row from the top with a pixel lighter than black, or nil where every pixel is black or transparent.
    var firstRowWithInk: Int? {
        (0 ..< height).first { row in
            (0 ..< width).contains { column in
                let pixel = pixel(column: column, row: row)
                return max(pixel.red, pixel.green, pixel.blue) > Self.inkThreshold
            }
        }
    }
}
