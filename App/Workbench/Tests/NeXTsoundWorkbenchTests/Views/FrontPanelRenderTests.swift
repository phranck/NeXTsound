import AppKit
import NeXTsoundCore
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import NeXTsoundWorkbench

extension RenderingTests {
    struct FrontPanelRenderTests {
        /// Every unlit dot of every display, the big one and the readouts alike, is a block of 3 × 3 device pixels in the
        /// ghost color at scale 2. A dot that lands between device pixels blends its edges into the glass, which leaves
        /// shorter runs of the exact ghost color.
        @Test func everyDotIsThreeByThreeDevicePixelsAtScaleTwo() async throws {
            let (panel, ghost) = try await MainActor.run {
                let profile = FactoryPreset.warm.makeProfile()
                let model = try WorkbenchModel(library: ProfileLibrary(profiles: [profile], selectedID: profile.id))
                let panel = FrontPanelView(model: model, driverLibrary: DriverLibraryModel())
                return try renderedWithMarker(panel, color: PhosphorTheme.blue.ghost)
            }
            Self.expectWholePixelDots(panel.runLengths(of: ghost), ghost: ghost)
        }

        /// The Library panel's readouts keep the same grid. Its AppKit views take no room, so an image render draws no
        /// placeholder over a dot.
        @Test func everyLibraryDotIsThreeByThreeDevicePixelsAtScaleTwo() async throws {
            let (panel, ghost) = try await MainActor.run {
                let profiles = ["Soul Funk", "Flat", "Warm"].map { SoundProfile(name: $0) }
                let model = try WorkbenchModel(library: ProfileLibrary(profiles: profiles, selectedID: profiles[0].id))
                let panel = LibraryPanel(model: model, driverLibrary: DriverLibraryModel())
                return try renderedWithMarker(panel, color: PhosphorTheme.blue.ghost)
            }
            Self.expectWholePixelDots(panel.runLengths(of: ghost), ghost: ghost)
        }

        /// The About window's readout keeps the same grid.
        @Test func everyAboutDotIsThreeByThreeDevicePixelsAtScaleTwo() async throws {
            let (panel, ghost) = try await MainActor.run {
                let info = AboutInfo(version: "1.2.0", build: "34", copyright: "© 2026 LAYERED.work")
                return try renderedWithMarker(AboutPanel(info: info, icon: NSImage()), color: PhosphorTheme.blue.ghost)
            }
            Self.expectWholePixelDots(panel.runLengths(of: ghost), ghost: ghost, minimumRuns: Self.minimumReadoutRuns)
        }

        /// The About window draws an app's icon as sharp as a bitmap of it at the frame's full resolution. An app's icon
        /// comes from IconServices at 32 points and renders at the size it is drawn at, so drawn at 32 points and scaled
        /// up to the frame, it would lose its fine detail.
        @Test func theAboutWindowDrawsItsIconAtFullResolution() async throws {
            let (drawn, reference) = try await MainActor.run {
                let icon = NSWorkspace.shared.icon(for: .applicationBundle)
                var frame = NSRect(x: 0, y: 0, width: AboutPanelLayout.iconSize, height: AboutPanelLayout.iconSize)
                let bitmap = try #require(icon.cgImage(forProposedRect: &frame, context: nil, hints: nil))
                let info = AboutInfo(version: "1.2.0", build: "34", copyright: nil)
                let sharp = NSImage(cgImage: bitmap, size: frame.size)
                return try (RenderedPixels(AboutPanel(info: info, icon: icon)), RenderedPixels(AboutPanel(info: info, icon: sharp)))
            }
            let region = Self.aboutIconRegion
            let referenceDetail = reference.meanNeighborDifference(columns: region.columns, rows: region.rows)
            #expect(drawn.meanNeighborDifference(columns: region.columns, rows: region.rows) >= referenceDetail * 0.97)
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

        /// The dots of the readouts and of the big display take their color from the environment, so a display color set
        /// there reaches every display.
        @Test func theDotsTakeTheEnvironmentsDisplayColor() async throws {
            let renders = try await MainActor.run {
                let readout = PanelReadout(text: "88888", layout: DotMatrixLinesLayout(cells: 5))
                let display = FrontPanelDisplay(
                    settings: FactoryPreset.warm.makeProfile().settings,
                    profileName: "Warm",
                    status: FrontPanelStatus(connection: "SoundBox connected", fields: []),
                    showsStatus: true
                )
                .frame(width: DotMatrixMetrics.size(columns: Self.gapTestColumns, rows: 1).width)
                return try [AnyView(readout), AnyView(display)].map { view in
                    try renderedWithMarker(view.environment(\.phosphorTheme, .amber), color: PhosphorTheme.amber.bright)
                }
            }
            for (pixels, lit) in renders {
                #expect(pixels.count(of: lit) > Self.minimumLitPixels)
            }
        }

        /// Each panel sets the display color it keeps over the one in the environment around it, so the color keys'
        /// choice is what its dots show. Nothing in a test stores a choice, so both panels keep blue, and an amber around
        /// them reaches none of their dots.
        @Test func eachPanelSetsTheDisplayColorItKeeps() async throws {
            let renders = try await MainActor.run {
                let profile = FactoryPreset.warm.makeProfile()
                let model = try WorkbenchModel(library: ProfileLibrary(profiles: [profile], selectedID: profile.id))
                let panels = [
                    AnyView(FrontPanelView(model: model, driverLibrary: DriverLibraryModel())),
                    AnyView(LibraryPanel(model: model, driverLibrary: DriverLibraryModel())),
                ]
                return try panels.map { panel in
                    try renderedWithMarker(panel.environment(\.phosphorTheme, .amber), color: PhosphorTheme.amber.bright)
                }
            }
            for (pixels, lit) in renders {
                #expect(pixels.count(of: lit) < Self.minimumLitPixels)
            }
        }

        /// While the display shows the spectrum, a band's bar lights from its level's row down and nothing above it, and
        /// the curve's solid 0 dB line gives way to the spectrum's dotted level line on the same row.
        @Test func theSpectrumTakesTheCurvesPlaceWhileItShows() async throws {
            let layout = FrontPanelDisplayLayout.self
            let curveColumns = layout.curveColumns(graphColumns: layout.graphColumns(displayColumns: Self.gapTestColumns))
            let spectrumBand = try #require(SpectrumBand.all.firstIndex { $0.lowerHz <= 2000 && $0.upperHz > 2000 })
            let barColumn = try #require(layout.spectrumBarColumns(SpectrumBand.all[spectrumBand], curveColumns: curveColumns)).lowerBound
            var decibels = SpectrumLevels.silent.decibels
            decibels[spectrumBand] = -25
            let topRow = layout.row(level: -25, rows: layout.graphRows)
            let lineDot = (column: layout.gainScaleColumns + 1, row: layout.row(decibels: 0, rows: layout.graphRows))
            let (spectrum, curve) = try await MainActor.run {
                try (Self.displayPixels(spectrum: SpectrumLevels(decibels: decibels)), Self.displayPixels(spectrum: nil))
            }
            #expect(Self.isLit(spectrum.dotPixel(column: layout.gainScaleColumns + barColumn, row: topRow)))
            #expect(!Self.isLit(spectrum.dotPixel(column: layout.gainScaleColumns + barColumn, row: topRow - 1)))
            #expect(Self.isLit(curve.dotPixel(column: lineDot.column, row: lineDot.row)))
            #expect(!Self.isLit(spectrum.dotPixel(column: lineDot.column, row: lineDot.row)))
        }
    }
}

private extension RenderingTests.FrontPanelRenderTests {
    /// The edge of one dot in device pixels at scale 2.
    static let dotPixels = 3
    /// The dot columns of the display the gap test renders.
    static let gapTestColumns = 400
    /// A channel above this shows a lit dot of the blue theme, whose unlit dots stay below 60.
    static let litThreshold = 128
    /// More than twenty lit dots of 3 × 3 device pixels, which a display in amber passes many times over, while the
    /// marker's own dot stays far below it.
    static let minimumLitPixels = 200
    /// The runs of the About window's one readout, whose several hundred unlit dots make six runs each.
    static let minimumReadoutRuns = 500
    /// The pixels of the About window's icon frame at scale 2: centered in the window's width, under its top padding.
    static var aboutIconRegion: (columns: Range<Int>, rows: Range<Int>) {
        let edge = Int(AboutPanelLayout.iconSize * 2)
        let left = Int(AboutPanelLayout.width - AboutPanelLayout.iconSize)
        let top = Int(AboutPanelLayout.padding.top * 2)
        return (left ..< left + edge, top ..< top + edge)
    }

    /// The pixel at the middle of the dot where the flat curve's 0 dB line meets the last gap column before the status
    /// column's place.
    @MainActor
    static func gapDotPixel(showsStatus: Bool) throws -> RenderedPixel {
        let gapColumn = FrontPanelDisplayLayout.statusColumn(displayColumns: gapTestColumns) - 1
        let zeroRow = FrontPanelDisplayLayout.row(decibels: 0, rows: FrontPanelDisplayLayout.graphRows)
        return try displayPixels(showsStatus: showsStatus).dotPixel(column: gapColumn, row: zeroRow)
    }

    /// Renders the display with a flat profile, `gapTestColumns` dot columns wide, showing `spectrum`, or the curve for
    /// nil.
    @MainActor
    static func displayPixels(showsStatus: Bool = true, spectrum: SpectrumLevels? = nil) throws -> RenderedPixels {
        let display = FrontPanelDisplay(
            settings: SoundProfile(name: "Flat").settings,
            profileName: "Flat",
            status: FrontPanelStatus(connection: "SoundBox connected", fields: []),
            showsStatus: showsStatus,
            spectrum: spectrum
        )
        .frame(width: DotMatrixMetrics.size(columns: gapTestColumns, rows: 1).width)
        return try RenderedPixels(display)
    }

    static func isLit(_ pixel: RenderedPixel) -> Bool {
        max(pixel.red, pixel.green, pixel.blue) > litThreshold
    }

    /// Expects every run of the ghost color to be a dot's length, and more of them than `minimumRuns`, which a whole
    /// panel's displays pass many times over. A failure names the color and the runs found of each length.
    static func expectWholePixelDots(
        _ runs: [Int: Int],
        ghost: RenderedPixel,
        minimumRuns: Int = 10000,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let found: Comment = "Runs of \(ghost) by length: \(runs.sorted { $0.key < $1.key })"
        #expect(runs.keys.sorted() == [dotPixels], found, sourceLocation: sourceLocation)
        #expect(runs[dotPixels, default: 0] > minimumRuns, found, sourceLocation: sourceLocation)
    }
}

/// A view rendered at scale 2 with one dot of `color` over its top leading corner, and the color that dot renders in.
///
/// The dot renders in the same pass as the view, so the comparison never rests on two renders producing the same
/// color. It is a dot's size, so its own pixels form runs of a dot's length.
@MainActor
private func renderedWithMarker(_ view: some View, color: Color) throws -> (pixels: RenderedPixels, marker: RenderedPixel) {
    let marked = ZStack(alignment: .topLeading) {
        view
        color
            .frame(width: DotMatrixMetrics.dotSize, height: DotMatrixMetrics.dotSize)
    }
    let pixels = try RenderedPixels(marked)
    return (pixels, pixels.pixel(column: 1, row: 1))
}

private extension RenderedPixels {
    /// The mean difference between horizontally neighboring pixels of a region, summed over the three channels. It is
    /// high where the region holds fine detail and low where that detail is blurred.
    func meanNeighborDifference(columns: Range<Int>, rows: Range<Int>) -> Double {
        var sum = 0
        var count = 0
        for row in rows {
            for column in columns.dropFirst() {
                let here = pixel(column: column, row: row)
                let left = pixel(column: column - 1, row: row)
                sum += abs(here.red - left.red) + abs(here.green - left.green) + abs(here.blue - left.blue)
                count += 1
            }
        }
        return count > 0 ? Double(sum) / Double(count) : 0
    }

    /// The pixel at the middle of the dot in `column` and `row` of a display rendered at scale 2.
    func dotPixel(column: Int, row: Int) -> RenderedPixel {
        let dot = DotMatrixMetrics.rect(column: column, row: row)
        return pixel(column: Int(dot.midX * 2), row: Int(dot.midY * 2))
    }

    /// How many pixels show `color`.
    func count(of color: RenderedPixel) -> Int {
        var count = 0
        for row in 0 ..< height {
            for column in 0 ..< width where pixel(column: column, row: row) == color {
                count += 1
            }
        }
        return count
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
