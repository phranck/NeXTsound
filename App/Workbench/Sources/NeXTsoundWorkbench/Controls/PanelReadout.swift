import SwiftUI

/// A small dot-matrix readout in its dark frame, such as the one above every slider.
///
/// Its dots keep their empty border inside the glass, so the rounded corners never clip one. The frame takes the
/// middle of the big display's shade.
struct PanelReadout: View {
    let lines: [DotMatrixLine]
    let layout: DotMatrixLinesLayout
    var alignment: DotMatrixAlignment = .leading

    var body: some View {
        DotMatrixLinesView(lines: lines, layout: layout, alignment: alignment)
            .vfdGlass(cornerRadius: PanelReadoutMetrics.glassRadius)
            .padding(FrontPanelLayout.frameWidth)
            .background(PanelReadoutMetrics.frameColor, in: RoundedRectangle(cornerRadius: PanelReadoutMetrics.frameRadius))
            .frameHighlight(cornerRadius: PanelReadoutMetrics.frameRadius, opacity: 0.05)
    }
}

extension PanelReadout {
    /// A readout of one bright line.
    init(text: String, layout: DotMatrixLinesLayout, alignment: DotMatrixAlignment = .leading) {
        self.init(lines: [DotMatrixLine(text: text)], layout: layout, alignment: alignment)
    }

    /// The layout of a readout of `lines` lines that fills `width` points, its frame included.
    static func fillingLayout(width: CGFloat, lines: Int = 1) -> DotMatrixLinesLayout {
        .filling(width: width - 2 * FrontPanelLayout.frameWidth, lines: lines)
    }
}

/// A readout's measurements, from the mockup.
private enum PanelReadoutMetrics {
    static let glassRadius: CGFloat = 5
    /// The frame's corners run parallel to the glass's, so its radius is the glass's plus the frame's width.
    static let frameRadius = glassRadius + FrontPanelLayout.frameWidth
    static let frameColor = Color(mixing: FrontPanelPalette.frameTop, FrontPanelPalette.frameBottom)
}
