import AppKit
import SwiftUI

/// The front panel's head: the NeXTSOUND wordmark between the four LAYERED stripes, all pressed into the metal.
///
/// The stripes are as tall as the wordmark's capitals and stand in the middle of the header's row. They fade out
/// toward the window's edges and take whatever width the wordmark leaves, which centers
/// the wordmark.
struct FrontPanelHeader: View {
    var body: some View {
        HStack(spacing: FrontPanelHeaderMetrics.spacing) {
            LayeredStripes(fade: .leading)
            FrontPanelWordmark()
            LayeredStripes(fade: .trailing)
        }
        .frame(height: FrontPanelHeaderMetrics.wordmarkSize)
        .padding(FrontPanelHeaderMetrics.padding)
    }
}

/// The wordmark in Bruno Ace, pressed into the metal and read out as the product's name.
///
/// Its letters are a recess in the metal. Their floor lies in shade and their upper edges in deeper shade, while their
/// lower edges catch the light that falls on the panels from above. Its baseline sits half a capital's height below
/// the middle of the header's row, so its capitals stand level with the stripes.
private struct FrontPanelWordmark: View {
    var body: some View {
        WordmarkGlyphs()
            .foregroundStyle(FrontPanelHeaderMetrics.pressed(FrontPanelHeaderMetrics.recessFloor))
            .background {
                PressedEdgeLight(outline: WordmarkGlyphs())
            }
            .fixedSize()
            .alignmentGuide(VerticalAlignment.center) { dimensions in
                dimensions[.firstTextBaseline] - FrontPanelHeaderMetrics.baselineBelowCenter
            }
            .accessibilityLabel(Text(verbatim: "NeXTsound"))
            .accessibilityAddTraits(.isHeader)
    }
}

/// The wordmark's letters in its face and spacing, in the color around them.
private struct WordmarkGlyphs: View {
    var body: some View {
        Text(verbatim: "NeXTSOUND")
            .font(.custom(FrontPanelFonts.wordmark, size: FrontPanelHeaderMetrics.wordmarkSize))
            .tracking(FrontPanelHeaderMetrics.wordmarkSize * FrontPanelHeaderMetrics.wordmarkTracking)
    }
}

/// The four bars of the LAYERED mark, stacked as the logo stacks them and fading out toward one side. Each bar is
/// pressed into the metal on its own and keeps its color.
private struct LayeredStripes: View {
    /// The side the bars fade out toward, which is the window's edge rather than the wordmark.
    let fade: HorizontalEdge

    var body: some View {
        VStack(spacing: FrontPanelHeaderMetrics.stripeGap) {
            ForEach(FrontPanelHeaderMetrics.stripeColors, id: \.self) { color in
                let bar = RoundedRectangle(cornerRadius: FrontPanelHeaderMetrics.stripeCornerRadius)
                bar
                    .fill(FrontPanelHeaderMetrics.pressed(color))
                    .background {
                        PressedEdgeLight(outline: bar)
                    }
                    .frame(height: FrontPanelHeaderMetrics.stripeHeight)
            }
        }
        .mask {
            // The fade reaches one edge's width below the bars, where the lowest bar's lit edge lies.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: FrontPanelHeaderMetrics.fadeLength),
                ],
                startPoint: fade == .leading ? .leading : .trailing,
                endPoint: fade == .leading ? .trailing : .leading
            )
            .padding(.bottom, -FrontPanelHeaderMetrics.edgeWidth)
        }
        .accessibilityHidden(true)
    }
}

/// The light along the lower edges of something pressed into the metal: its outline one edge's width lower, less the
/// outline itself, so the light shows only where an edge faces up toward the light.
private struct PressedEdgeLight<Outline: View>: View {
    /// The pressed shape, whose opaque parts give the light its outline and cut it away again.
    let outline: Outline

    var body: some View {
        ZStack {
            FrontPanelHeaderMetrics.edgeLight
                .mask {
                    outline
                }
                .offset(y: FrontPanelHeaderMetrics.edgeWidth)
            outline
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}

/// The header's measurements. The stripes' proportions and colors are the LAYERED logo's.
private enum FrontPanelHeaderMetrics {
    static let wordmarkSize: CGFloat = 34
    static let wordmarkTracking: CGFloat = 0.04
    /// The shade on the floor of the wordmark's recess, over the metal.
    static let recessFloor = Color.black.opacity(0.28)
    /// The deeper shade along the upper edges of everything pressed into the metal, which face away from the light.
    static let recessShade = Color.black.opacity(0.75)
    /// The light along the lower edges of everything pressed into the metal, which face up toward the light.
    static let edgeLight = Color.white.opacity(0.22)
    /// The width of the shade along the upper edges and of the light along the lower ones.
    static let edgeWidth: CGFloat = 1
    static let spacing: CGFloat = 22
    static let padding = EdgeInsets(top: 4, leading: 36, bottom: 18, trailing: 36)
    /// A bar is a little over three times the gap below it, as in the logo.
    static let stripeGapRatio: CGFloat = 0.3
    static let stripeCornerRadius: CGFloat = 1
    /// The share of a stripe block over which it fades in from the window's edge.
    static let fadeLength: CGFloat = 0.45
    /// The LAYERED colors, the ones Prommer's `Color.layeredStripes` holds.
    static let stripeColors: [Color] = [
        Color(hex: FrontPanelPalette.stripeRed),
        Color(hex: FrontPanelPalette.stripeYellow),
        Color(hex: 0x758C34),
        Color(hex: 0x2B7488),
    ]

    /// A fill pressed into the metal: `fill` with the deeper shade inside its upper edges.
    static func pressed(_ fill: Color) -> some ShapeStyle {
        fill.shadow(.inner(color: recessShade, radius: edgeWidth, y: edgeWidth))
    }

    /// The height of the wordmark's capitals, which the stripes and the wordmark's baseline both take their measure
    /// from. It is read each time, because the face is only found once the front panel has registered it.
    static var capHeight: CGFloat {
        let font = NSFont(name: FrontPanelFonts.wordmark, size: wordmarkSize) ?? .systemFont(ofSize: wordmarkSize)
        return font.capHeight
    }

    /// The distance from the middle of the header's row down to the wordmark's baseline, which centers its capitals
    /// on the row, where the stripes stand.
    static var baselineBelowCenter: CGFloat {
        capHeight / 2
    }

    /// The height of one bar, so that the four bars and their gaps stand as tall as the wordmark's capitals.
    static var stripeHeight: CGFloat {
        let count = CGFloat(stripeColors.count)
        return capHeight / (count + (count - 1) * stripeGapRatio)
    }

    static var stripeGap: CGFloat {
        stripeHeight * stripeGapRatio
    }
}
