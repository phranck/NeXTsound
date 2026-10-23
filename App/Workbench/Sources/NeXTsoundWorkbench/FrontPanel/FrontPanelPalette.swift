import AppKit
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
    /// A lit LED and a lit legend.
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
    /// The line height SwiftUI sets the face in, which `NSLayoutManager.defaultLineHeight(for:)` reports as well.
    static let textLineHeight: CGFloat = 14
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

/// A control's caption in capitals, under its control or beside its LED.
///
/// A caption on one line that is wider than its control stays centered under it and reaches past both of its sides.
/// A caption given a width breaks into lines at it.
struct ControlCaption: View {
    let caption: Text
    /// The width a caption breaks into lines at, or nil for one line.
    var wrapWidth: CGFloat?
    /// Where the lines of a caption that breaks sit: centered under a control, or flush beside an LED.
    var alignment = TextAlignment.center
    /// The letter spacing, which a momentary key's caption drops so its whole word stays clear of its neighbor's.
    var tracking = FrontPanelType.captionTracking

    var body: some View {
        if let wrapWidth {
            styledCaption
                .multilineTextAlignment(alignment)
                .lineSpacing(Self.leading)
                .padding(.vertical, Self.leading / 2)
                .frame(width: wrapWidth, alignment: frameAlignment)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            styledCaption
                .lineLimit(1)
                .fixedSize()
                .frame(height: FrontPanelType.lineHeight)
        }
    }
}

extension ControlCaption {
    /// A caption as narrow as its widest word, which breaks between its words wherever the next one no longer fits,
    /// as a caption beside an LED or under a single key does.
    init(wrappingToWidestWord caption: String, alignment: TextAlignment = .center) {
        self.init(caption: Text(verbatim: caption), wrapWidth: Self.widestWord(of: caption), alignment: alignment)
    }
}

private extension ControlCaption {
    /// What a line of the mockup's type is taller than a line of SwiftUI's. It goes between the lines of a caption
    /// that breaks, and half of it above and below the caption, as CSS shares a line's leading out, so every line
    /// stands where the mockup's does.
    static let leading = FrontPanelType.lineHeight - FrontPanelType.textLineHeight

    /// The width of the widest word of a caption in capitals with the caption's letter spacing, rounded up to whole
    /// points, because SwiftUI rounds a text's width to device pixels and would otherwise break the word itself.
    static func widestWord(of text: String) -> CGFloat {
        guard let font = NSFont(name: FrontPanelFonts.captions, size: FrontPanelType.size) else {
            return 0
        }
        let widths = text.uppercased().split(separator: " ").map { word in
            NSAttributedString(string: String(word), attributes: [.font: font, .kern: FrontPanelType.captionTracking]).size().width
        }
        return (widths.max() ?? 0).rounded(.up)
    }

    var frameAlignment: Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var styledCaption: some View {
        caption
            .font(FrontPanelType.font)
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundStyle(FrontPanelPalette.caption)
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
