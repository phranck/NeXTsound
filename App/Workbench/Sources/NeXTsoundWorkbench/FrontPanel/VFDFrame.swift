import SwiftUI

extension View {
    /// Puts a display's glass behind the view, with a light edge along its top and left and a dark one along its
    /// bottom and right, as every display in the mockup has.
    func vfdGlass(cornerRadius: CGFloat) -> some View {
        background(
            PhosphorTheme.glass
                .shadow(.inner(color: .white.opacity(0.03), radius: 0, x: 1, y: 1))
                .shadow(.inner(color: .black.opacity(0.6), radius: 0, x: -1, y: -1)),
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
    }

    /// Lays a faint highlight one point under the view's rounded outline, where a frame's lower edge catches the
    /// light.
    func frameHighlight(cornerRadius: CGFloat, opacity: Double) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.white.opacity(opacity))
                .offset(y: 1)
        }
    }
}

/// A small dot-matrix readout in its dark frame, such as the one above every slider.
///
/// Its dots keep their empty border inside the glass, so the rounded corners never clip one. The frame takes the
/// middle of the big display's shade.
struct PanelReadout: View {
    let text: String
    let layout: DotMatrixLinesLayout
    var alignment: DotMatrixAlignment = .leading
    let theme: PhosphorTheme

    var body: some View {
        DotMatrixLinesView(lines: [DotMatrixLine(text: text)], layout: layout, alignment: alignment, theme: theme)
            .vfdGlass(cornerRadius: PanelReadoutMetrics.glassRadius)
            .padding(FrontPanelLayout.frameWidth)
            .background(PanelReadoutMetrics.frameColor, in: RoundedRectangle(cornerRadius: PanelReadoutMetrics.frameRadius))
            .frameHighlight(cornerRadius: PanelReadoutMetrics.frameRadius, opacity: 0.05)
    }
}

/// A readout's measurements, from the mockup.
private enum PanelReadoutMetrics {
    static let glassRadius: CGFloat = 5
    /// The frame's corners run parallel to the glass's, so its radius is the glass's plus the frame's width.
    static let frameRadius = glassRadius + FrontPanelLayout.frameWidth
    static let frameColor = Color(mixing: FrontPanelPalette.frameTop, FrontPanelPalette.frameBottom)
}
