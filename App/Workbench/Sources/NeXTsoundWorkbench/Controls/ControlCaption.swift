import AppKit
import SwiftUI

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
        guard let font = FrontPanelType.appKitFont else {
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
