import SwiftUI

/// The colors the front panel's controls share, from the mockup's tokens.
///
/// A shade that only one control uses stays with that control.
enum FrontPanelPalette {
    /// A panel's title.
    static let title = Color(hex: 0xCFCBBD)
    /// A control's caption.
    static let captionShade: UInt32 = 0x9B968A
    static let caption = Color(hex: captionShade)
    /// A lit LED, a lit legend and a focused control's halo.
    static let cyan = Color(hex: 0x00FFD8)
    /// The dark ring around a track and a cap.
    static let outline = Color.black.opacity(0.6)
    /// The lines engraved into a control's surface.
    static let engraving = Color(hex: 0x474747)
    /// The top of a display frame's shade.
    static let frameTop: UInt32 = 0x16181A
    /// The bottom of a display frame's shade.
    static let frameBottom: UInt32 = 0x0C0D0E
}

/// The type of the panel's titles and captions: JetBrains Mono at 11 pt.
enum FrontPanelType {
    static let size: CGFloat = 11
    /// One line, the face's ascender and descender at that size.
    static let lineHeight: CGFloat = 14.5
    /// A title's letter spacing of 0.14 em.
    static let titleTracking = size * 0.14
    /// A caption's letter spacing of 0.06 em.
    static let captionTracking = size * 0.06

    static var font: Font {
        .custom(FrontPanelFonts.captions, size: size)
    }
}

/// The front panel's motion: the mockup's 180 ms ease for a change of state, and 80 ms with reduced motion.
enum FrontPanelMotion {
    static func state(reduceMotion: Bool) -> Animation {
        .timingCurve(0.3, 0.7, 0.4, 1, duration: reduceMotion ? 0.08 : 0.18)
    }
}

/// A panel's title in capitals over a faint rule, one line high.
struct PanelTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FrontPanelType.font)
                .tracking(FrontPanelType.titleTracking)
                .textCase(.uppercase)
                .foregroundStyle(FrontPanelPalette.title)
                .lineLimit(1)
                .fixedSize()
                .frame(height: FrontPanelType.lineHeight)
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(height: 1)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// A control's caption in capitals, on one line under the control.
///
/// A caption wider than its control stays centered under it and reaches past both of its sides.
struct ControlCaption: View {
    let caption: Text

    var body: some View {
        caption
            .font(FrontPanelType.font)
            .tracking(FrontPanelType.captionTracking)
            .textCase(.uppercase)
            .foregroundStyle(FrontPanelPalette.caption)
            .lineLimit(1)
            .fixedSize()
            .frame(height: FrontPanelType.lineHeight)
    }
}

/// The cyan halo around a focused control: a ring two points wide and a glow around it.
struct FocusHalo<HaloShape: InsettableShape>: View {
    let shape: HaloShape
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            shape
                .inset(by: -3)
                .fill(FrontPanelPalette.cyan.opacity(0.5))
                .blur(radius: 5)
            shape
                .inset(by: -1)
                .stroke(FrontPanelPalette.cyan, lineWidth: 2)
        }
        .opacity(isVisible ? 1 : 0)
        .animation(FrontPanelMotion.state(reduceMotion: reduceMotion), value: isVisible)
        .allowsHitTesting(false)
    }
}

/// A CSS `inset` box shadow on a shape: the shade its outside casts inward, offset and blurred, at full strength
/// whatever the shape is filled with.
///
/// SwiftUI's inner shadow style takes its strength from the fill it shades, so on a translucent fill it fades with the
/// fill, while the mockup's inset shadows keep their own opacity. The blur is given as CSS gives it, twice the
/// Gaussian's deviation.
struct InsetShadow<ShadowShape: Shape>: View {
    let shape: ShadowShape
    let color: Color
    var blur: CGFloat = 0
    var offset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let reach = blur * 2 + max(abs(offset.width), abs(offset.height)) + 1
            Path { outside in
                outside.addRect(bounds.insetBy(dx: -reach, dy: -reach))
                outside.addPath(shape.path(in: bounds))
            }
            .fill(color, style: FillStyle(eoFill: true))
            .offset(offset)
            .blur(radius: blur / 2)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}
