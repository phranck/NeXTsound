import SwiftUI

/// A round push button built like the kit's red power button.
///
/// A dark ring holds a cap shaded from top to bottom, whose upper rim catches the light while its lower rim lies in
/// shade, and the button sits in the same recess as every other control. The light one saves, and the red one marks
/// the one action that rewrites the board.
struct PanelPushButton: View {
    /// What VoiceOver calls the button.
    let label: LocalizedStringKey
    let kind: PanelPushButtonKind
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            EmptyView()
        }
        .buttonStyle(PanelPushButtonStyle(kind: kind, isFocused: isFocused))
        .focused($isFocused)
        .focusEffectDisabled()
        .accessibilityLabel(label)
    }
}

/// Which of the two push buttons a button is: the light save button or the red flash button.
enum PanelPushButtonKind {
    case save
    case flash
}

private struct PanelPushButtonStyle: ButtonStyle {
    let kind: PanelPushButtonKind
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        PanelPushButtonFace(kind: kind, isPressed: configuration.isPressed, isFocused: isFocused)
    }
}

/// The recess, the dark ring, the cap and its engraved glyph. A pressed cap sinks a little and casts less shadow.
private struct PanelPushButtonFace: View {
    let kind: PanelPushButtonKind
    let isPressed: Bool
    let isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.black.opacity(0.4), .white.opacity(0.16)], startPoint: .top, endPoint: .bottom))
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: PanelPushButtonMetrics.capSize, height: PanelPushButtonMetrics.capSize)
                .blur(radius: isPressed ? 0.5 : 2)
                .offset(y: isPressed ? 1 : 3)
            Circle()
                .fill(Color(hex: 0x111111))
                .frame(width: PanelPushButtonMetrics.ringSize, height: PanelPushButtonMetrics.ringSize)
            PanelPushButtonCap(kind: kind)
                .scaleEffect(isPressed ? 0.97 : 1)
        }
        .frame(width: PanelPushButtonMetrics.size, height: PanelPushButtonMetrics.size)
        .background {
            FocusHalo(shape: Circle(), isVisible: isFocused)
        }
        .contentShape(Circle())
        .animation(FrontPanelMotion.state(reduceMotion: reduceMotion), value: isPressed)
    }
}

/// The cap, lit from above, with its glyph engraved into it.
private struct PanelPushButtonCap: View {
    let kind: PanelPushButtonKind

    var body: some View {
        let shades = PanelPushButtonMetrics.shades(of: kind)
        Circle()
            .fill(
                LinearGradient(colors: [Color(hex: shades.top), Color(hex: shades.bottom)], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: Color(hex: shades.rimLight), radius: 0, y: 2))
                    .shadow(.inner(color: Color(hex: shades.rimDark), radius: 0, y: -2))
            )
            .overlay {
                PanelPushButtonGlyph(kind: kind)
                    .foregroundStyle(Color(hex: shades.engraving))
                    .shadow(color: shades.emboss, radius: 0, y: 1)
                    .frame(width: PanelPushButtonMetrics.glyphSize, height: PanelPushButtonMetrics.glyphSize)
            }
            .frame(width: PanelPushButtonMetrics.capSize, height: PanelPushButtonMetrics.capSize)
    }
}

/// The mockup's glyphs on a 24-point grid: an arrow down into a tray for saving, a lightning bolt for flashing.
private struct PanelPushButtonGlyph: View {
    let kind: PanelPushButtonKind

    var body: some View {
        switch kind {
        case .save:
            SaveGlyph()
                .stroke(style: StrokeStyle(lineWidth: 2.4 * PanelPushButtonMetrics.glyphScale, lineCap: .round, lineJoin: .round))
        case .flash:
            FlashGlyph()
                .fill()
        }
    }
}

private struct SaveGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 12, y: 4))
        path.addLine(to: CGPoint(x: 12, y: 13.5))
        path.move(to: CGPoint(x: 7.5, y: 9.5))
        path.addLine(to: CGPoint(x: 12, y: 14))
        path.addLine(to: CGPoint(x: 16.5, y: 9.5))
        path.move(to: CGPoint(x: 5, y: 15.5))
        path.addLine(to: CGPoint(x: 5, y: 19))
        path.addLine(to: CGPoint(x: 19, y: 19))
        path.addLine(to: CGPoint(x: 19, y: 15.5))
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}

private struct FlashGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 13.5, y: 2.5))
        path.addLine(to: CGPoint(x: 5.5, y: 13.5))
        path.addLine(to: CGPoint(x: 11, y: 13.5))
        path.addLine(to: CGPoint(x: 10, y: 21.5))
        path.addLine(to: CGPoint(x: 18, y: 10.5))
        path.addLine(to: CGPoint(x: 12.5, y: 10.5))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}

/// A push button's measurements and shades, from the mockup.
private enum PanelPushButtonMetrics {
    static let size: CGFloat = 52
    /// The recess around the ring.
    static let well: CGFloat = 6
    static let capSize = size - 2 * well
    static let ringSize = capSize + 2 * 4
    /// The glyph covers 44 percent of the cap.
    static let glyphSize = capSize * 0.44
    /// The glyph's size against the 24-point grid it is drawn on.
    static let glyphScale = glyphSize / 24

    struct Shades {
        let top: UInt32
        let bottom: UInt32
        let rimLight: UInt32
        let rimDark: UInt32
        let engraving: UInt32
        let emboss: Color
    }

    static func shades(of kind: PanelPushButtonKind) -> Shades {
        switch kind {
        case .save:
            Shades(top: 0x666666, bottom: 0xE6E6E6, rimLight: 0xEBEBEB, rimDark: 0x747474, engraving: 0x474747, emboss: .white.opacity(0.5))
        case .flash:
            Shades(
                top: 0x74030B,
                bottom: 0xDE0C2C,
                rimLight: 0xE00A25,
                rimDark: 0x820106,
                engraving: 0x3A0919,
                emboss: Color(red: 1, green: 130 / 255, blue: 130 / 255).opacity(0.35)
            )
        }
    }
}
