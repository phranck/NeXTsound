import CoreGraphics
import NeXTsoundCore
import SwiftUI
import Testing
@testable import NeXTsoundWorkbench

struct FrontPanelDisplayLayoutTests {
    @Test func gainFallsOnTheCurvesRowsAroundZeroDecibels() {
        #expect(FrontPanelDisplayLayout.row(decibels: 0, rows: 97) == 48)
        #expect(FrontPanelDisplayLayout.row(decibels: FrontPanelDisplayLayout.decibelRange, rows: 97) == 0)
        #expect(FrontPanelDisplayLayout.row(decibels: 100, rows: 97) == 0)
        #expect(FrontPanelDisplayLayout.row(decibels: -100, rows: 97) == 96)
        #expect(FrontPanelDisplayLayout.row(decibels: .nan, rows: 97) == 48)
    }

    @Test func theFrequencyRangeSpansTheCurvesColumns() {
        #expect(FrontPanelDisplayLayout.column(frequencyHz: 20, columns: 343) == 0)
        #expect(FrontPanelDisplayLayout.column(frequencyHz: 20000, columns: 343) == 342)
        #expect(FrontPanelDisplayLayout.column(frequencyHz: 1000, columns: 343).map { (1 ..< 342).contains($0) } == true)
    }

    @Test func theCurveKeepsTwoColumnsOnANarrowDisplay() {
        #expect(FrontPanelDisplayLayout.graphColumns(displayColumns: 10) == 2)
    }
}

struct FrontPanelRenderTests {
    /// Every dot of the display is a block of 3 × 3 pixels in one color at scale 2, and the pixel column and row
    /// after it show the glass. A dot that lands between device pixels blends into its neighbors and fails both.
    @Test func everyDotIsThreeByThreeDevicePixelsAtScaleTwo() async throws {
        let dotPixels = 3
        let pitchPixels = 4
        let (panel, ghost) = try await MainActor.run {
            let profile = FactoryPreset.warm.makeProfile()
            let model = try WorkbenchModel(library: ProfileLibrary(profiles: [profile], selectedID: profile.id))
            let panel = try RenderedPixels(FrontPanelView(model: model))
            let ghost = try RenderedPixels(PhosphorTheme.blue.ghost.frame(width: 1, height: 1)).pixel(column: 0, row: 0)
            return (panel, ghost)
        }
        let grid = try #require(panel.bounds(of: ghost))
        #expect(grid.width > 1000 && grid.height > 400)
        var strayPixels = 0
        for row in grid.minY ..< grid.maxY {
            for column in grid.minX ..< grid.maxX {
                let phase = (column: (column - grid.minX) % pitchPixels, row: (row - grid.minY) % pitchPixels)
                let pixel = panel.pixel(column: column, row: row)
                let isGlass = pixel.isDarker(thanHalfOf: ghost)
                if phase.column == dotPixels || phase.row == dotPixels {
                    strayPixels += isGlass ? 0 : 1
                } else {
                    let dotCorner = panel.pixel(column: column - phase.column, row: row - phase.row)
                    strayPixels += !isGlass && pixel == dotCorner ? 0 : 1
                }
            }
        }
        #expect(strayPixels == 0)
        #expect(grid.width % pitchPixels == dotPixels && grid.height % pitchPixels == dotPixels)
    }
}

/// The pixels of a view rendered at scale 2, as 8-bit sRGB with the top row first.
///
/// Only the rendering needs the main actor. The pixels can be read anywhere, so a scan of millions of them leaves
/// the main actor to the tests running beside it.
private struct RenderedPixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    @MainActor init(_ content: some View) throws {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return context != nil
        }
        try #require(drawn)
        self.bytes = bytes
    }
}

private extension RenderedPixels {
    func pixel(column: Int, row: Int) -> RenderedPixel {
        let offset = (row * width + column) * 4
        return RenderedPixel(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
    }

    /// The smallest pixel rectangle holding every pixel of one color, or nil when none has it.
    func bounds(of color: RenderedPixel) -> PixelRect? {
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        for row in 0 ..< height {
            for column in 0 ..< width where pixel(column: column, row: row) == color {
                minX = min(minX, column)
                minY = min(minY, row)
                maxX = max(maxX, column + 1)
                maxY = max(maxY, row + 1)
            }
        }
        return minX < maxX ? PixelRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY) : nil
    }
}

private struct RenderedPixel: Equatable {
    let red: Int
    let green: Int
    let blue: Int

    /// Whether every channel is under half of another color's, which holds for the glass against the unlit dots and
    /// fails for a dot's edge blended into the glass.
    func isDarker(thanHalfOf other: RenderedPixel) -> Bool {
        red * 2 < other.red && green * 2 < other.green && blue * 2 < other.blue
    }
}

private struct PixelRect {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int

    var width: Int {
        maxX - minX
    }

    var height: Int {
        maxY - minY
    }
}
