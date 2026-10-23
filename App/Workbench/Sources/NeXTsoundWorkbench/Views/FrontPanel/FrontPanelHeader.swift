import AppKit
import SwiftUI

/// The front panel's head: the NeXTSOUND wordmark between the four LAYERED stripes.
///
/// The stripes are as tall as the wordmark's capitals and stand in the middle of the header's row, as the mockup
/// centers them. They fade out toward the window's edges and take whatever width the wordmark leaves, which centers
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

/// The wordmark in Bruno Ace, read out as the product's name.
///
/// Its baseline sits half a capital's height below the middle of the header's row, so its capitals stand level with
/// the stripes.
private struct FrontPanelWordmark: View {
    var body: some View {
        Text(verbatim: "NeXTSOUND")
            .font(.custom(FrontPanelFonts.wordmark, size: FrontPanelHeaderMetrics.wordmarkSize))
            .tracking(FrontPanelHeaderMetrics.wordmarkSize * FrontPanelHeaderMetrics.wordmarkTracking)
            .foregroundStyle(FrontPanelHeaderMetrics.wordmarkColor)
            .shadow(color: .black.opacity(0.6), radius: 0, y: 1)
            .shadow(color: FrontPanelHeaderMetrics.wordmarkColor.opacity(0.15), radius: 9)
            .fixedSize()
            .alignmentGuide(VerticalAlignment.center) { dimensions in
                dimensions[.firstTextBaseline] - FrontPanelHeaderMetrics.baselineBelowCenter
            }
            .accessibilityLabel(Text(verbatim: "NeXTsound"))
            .accessibilityAddTraits(.isHeader)
    }
}

/// The four bars of the LAYERED mark, stacked as the logo stacks them and fading out toward one side.
private struct LayeredStripes: View {
    /// The side the bars fade out toward, which is the window's edge rather than the wordmark.
    let fade: HorizontalEdge

    var body: some View {
        VStack(spacing: FrontPanelHeaderMetrics.stripeGap) {
            ForEach(FrontPanelHeaderMetrics.stripeColors, id: \.self) { color in
                RoundedRectangle(cornerRadius: FrontPanelHeaderMetrics.stripeCornerRadius)
                    .fill(color)
                    .frame(height: FrontPanelHeaderMetrics.stripeHeight)
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: FrontPanelHeaderMetrics.fadeLength),
                ],
                startPoint: fade == .leading ? .leading : .trailing,
                endPoint: fade == .leading ? .trailing : .leading
            )
        )
        .accessibilityHidden(true)
    }
}

/// The header's measurements, from the mockup and from the LAYERED logo.
private enum FrontPanelHeaderMetrics {
    static let wordmarkSize: CGFloat = 34
    static let wordmarkTracking: CGFloat = 0.04
    static let wordmarkColor = Color(hex: 0xE8E4D8)
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
