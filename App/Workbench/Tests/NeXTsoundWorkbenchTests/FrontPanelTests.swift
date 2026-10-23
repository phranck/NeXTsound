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
    /// Every unlit dot of every display, the big one and the readouts alike, is a block of 3 × 3 device pixels in the
    /// ghost color at scale 2. A dot that lands between device pixels blends its edges into the glass, which leaves
    /// shorter runs of the exact ghost color.
    @Test func everyDotIsThreeByThreeDevicePixelsAtScaleTwo() async throws {
        let (panel, ghost) = try await MainActor.run {
            let profile = FactoryPreset.warm.makeProfile()
            let model = try WorkbenchModel(library: ProfileLibrary(profiles: [profile], selectedID: profile.id))
            return try renderedWithGhost(FrontPanelView(model: model, libraryWindow: LibraryWindowAttachment()))
        }
        Self.expectWholePixelDots(panel.runLengths(of: ghost), ghost: ghost)
    }

    /// The Library panel's readouts keep the same grid. Its AppKit views take no room, so an image render draws no
    /// placeholder over a dot.
    @Test func everyLibraryDotIsThreeByThreeDevicePixelsAtScaleTwo() async throws {
        let (panel, ghost) = try await MainActor.run {
            let profiles = ["Soul Funk", "Flat", "Warm"].map { SoundProfile(name: $0) }
            let model = try WorkbenchModel(library: ProfileLibrary(profiles: profiles, selectedID: profiles[0].id))
            return try renderedWithGhost(LibraryPanel(
                model: model,
                driverLibrary: DriverLibraryModel(),
                libraryWindow: LibraryWindowAttachment()
            ))
        }
        Self.expectWholePixelDots(panel.runLengths(of: ghost), ghost: ghost)
    }
}

private extension FrontPanelRenderTests {
    /// The edge of one dot in device pixels at scale 2.
    static let dotPixels = 3

    /// Expects every run of the ghost color to be a dot's length, and many of them. A failure names the color and the
    /// runs found of each length.
    static func expectWholePixelDots(_ runs: [Int: Int], ghost: RenderedPixel, sourceLocation: SourceLocation = #_sourceLocation) {
        let found: Comment = "Runs of \(ghost) by length: \(runs.sorted { $0.key < $1.key })"
        #expect(runs.keys.sorted() == [dotPixels], found, sourceLocation: sourceLocation)
        #expect(runs[dotPixels, default: 0] > 10000, found, sourceLocation: sourceLocation)
    }
}

/// A view rendered at scale 2 with one ghost dot of the blue theme over its top leading corner, and the color that dot
/// renders in.
///
/// The dot renders in the same pass as the view, so the comparison never rests on two renders producing the same
/// color. It is a dot's size, so its own pixels form runs of a dot's length.
@MainActor
private func renderedWithGhost(_ view: some View) throws -> (pixels: RenderedPixels, ghost: RenderedPixel) {
    let marked = ZStack(alignment: .topLeading) {
        view
        PhosphorTheme.blue.ghost
            .frame(width: DotMatrixMetrics.dotSize, height: DotMatrixMetrics.dotSize)
    }
    let pixels = try RenderedPixels(marked)
    return (pixels, pixels.pixel(column: 1, row: 1))
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

    /// How often each length of an unbroken run of one color occurs, along every row and along every column.
    func runLengths(of color: RenderedPixel) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        func close(_ length: inout Int) {
            if length > 0 {
                counts[length, default: 0] += 1
            }
            length = 0
        }
        for row in 0 ..< height {
            var length = 0
            for column in 0 ..< width {
                if pixel(column: column, row: row) == color {
                    length += 1
                } else {
                    close(&length)
                }
            }
            close(&length)
        }
        for column in 0 ..< width {
            var length = 0
            for row in 0 ..< height {
                if pixel(column: column, row: row) == color {
                    length += 1
                } else {
                    close(&length)
                }
            }
            close(&length)
        }
        return counts
    }
}

private struct RenderedPixel: Equatable {
    let red: Int
    let green: Int
    let blue: Int
}
