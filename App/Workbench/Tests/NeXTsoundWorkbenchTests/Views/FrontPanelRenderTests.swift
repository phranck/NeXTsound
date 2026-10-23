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

    /// The status column slides out by the columns it takes from the curve, in whole dot columns, and the curve takes
    /// the whole display once the column is out.
    @Test func theStatusColumnSlidesOutByTheColumnsItTakesFromTheCurve() {
        let reserved = FrontPanelDisplayLayout.statusReservedColumns
        #expect(FrontPanelDisplayLayout.statusShift(reveal: 1) == 0)
        #expect(FrontPanelDisplayLayout.statusShift(reveal: 0) == reserved)
        #expect(FrontPanelDisplayLayout.statusShift(reveal: 0.5) == Int((Double(reserved) / 2).rounded()))
        #expect(FrontPanelDisplayLayout.statusShift(reveal: .nan) == 0)
        #expect(FrontPanelDisplayLayout.graphColumns(displayColumns: 500, statusShift: reserved) == 500)
        #expect(FrontPanelDisplayLayout.statusColumn(displayColumns: 500, statusShift: reserved) >= 500)
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
            return try renderedWithGhost(FrontPanelView(model: model, driverLibrary: DriverLibraryModel()))
        }
        Self.expectWholePixelDots(panel.runLengths(of: ghost), ghost: ghost)
    }

    /// The Library panel's readouts keep the same grid. Its AppKit views take no room, so an image render draws no
    /// placeholder over a dot.
    @Test func everyLibraryDotIsThreeByThreeDevicePixelsAtScaleTwo() async throws {
        let (panel, ghost) = try await MainActor.run {
            let profiles = ["Soul Funk", "Flat", "Warm"].map { SoundProfile(name: $0) }
            let model = try WorkbenchModel(library: ProfileLibrary(profiles: profiles, selectedID: profiles[0].id))
            return try renderedWithGhost(LibraryPanel(model: model, driverLibrary: DriverLibraryModel()))
        }
        Self.expectWholePixelDots(panel.runLengths(of: ghost), ghost: ghost)
    }

    /// While the status column is out, the curve's 0 dB line runs through the gap that stands before the column while
    /// it is in, because the curve takes the room the column leaves.
    @Test func theCurveTakesTheStatusColumnsRoomWhileTheColumnIsOut() async throws {
        let (shown, hidden) = try await MainActor.run {
            try (Self.gapDotPixel(showsStatus: true), Self.gapDotPixel(showsStatus: false))
        }
        #expect(!Self.isLit(shown))
        #expect(Self.isLit(hidden))
    }
}

private extension FrontPanelRenderTests {
    /// The edge of one dot in device pixels at scale 2.
    static let dotPixels = 3
    /// The dot columns of the display the gap test renders.
    static let gapTestColumns = 400
    /// A channel above this shows a lit dot of the blue theme, whose unlit dots stay below 60.
    static let litThreshold = 128

    /// Renders the display with a flat profile and returns the pixel at the middle of the dot where the 0 dB line
    /// meets the last gap column before the status column's place.
    @MainActor
    static func gapDotPixel(showsStatus: Bool) throws -> RenderedPixel {
        let gapColumn = FrontPanelDisplayLayout.statusColumn(displayColumns: gapTestColumns) - 1
        let zeroRow = FrontPanelDisplayLayout.row(decibels: 0, rows: FrontPanelDisplayLayout.graphRows)
        let dot = DotMatrixMetrics.rect(column: gapColumn, row: zeroRow)
        let display = FrontPanelDisplay(
            settings: SoundProfile(name: "Flat").settings,
            profileName: "Flat",
            status: FrontPanelStatus(connection: "SoundBox connected", fields: []),
            showsStatus: showsStatus,
            theme: .blue
        )
        .frame(width: DotMatrixMetrics.size(columns: gapTestColumns, rows: 1).width)
        return try RenderedPixels(display).pixel(column: Int(dot.midX * 2), row: Int(dot.midY * 2))
    }

    static func isLit(_ pixel: RenderedPixel) -> Bool {
        max(pixel.red, pixel.green, pixel.blue) > litThreshold
    }

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

private extension RenderedPixels {
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
