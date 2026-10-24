import SwiftUI

/// The kit's slide toggle for an on/off setting.
///
/// While the setting is on, the knob sits left beside the lit ON legend, and while it is off it sits right beside the
/// OFF legend. The toggle is drawn at the size of the kit's reference image and scaled to the panel, so every
/// measurement in it reads as it does in the image. A click gives it the keyboard's focus without showing a ring, Space
/// then toggles it, and VoiceOver reads it as a switch.
struct SlideToggle: View {
    /// What VoiceOver calls the toggle.
    let label: LocalizedStringKey
    @Binding var isOn: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        SlideToggleBody(isOn: isOn)
            .scaleEffect(SlideToggleMetrics.zoom, anchor: .topLeading)
            .frame(
                width: SlideToggleMetrics.size.width * SlideToggleMetrics.zoom,
                height: SlideToggleMetrics.size.height * SlideToggleMetrics.zoom,
                alignment: .topLeading
            )
            .contentShape(RoundedRectangle(cornerRadius: SlideToggleMetrics.radius * SlideToggleMetrics.zoom))
            .onTapGesture {
                isOn.toggle()
                isFocused = true
            }
            .panelFocus($isFocused)
            .onKeyPress(.space) {
                isOn.toggle()
                return .handled
            }
            .accessibilityRepresentation {
                Toggle(label, isOn: $isOn)
            }
    }
}

/// The toggle at the reference image's size: the recess ring, the track and the knob.
private struct SlideToggleBody: View {
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            SlideToggleRecess(isOn: isOn)
            SlideToggleTrack(isOn: isOn)
                .offset(x: SlideToggleMetrics.ring, y: SlideToggleMetrics.ring)
        }
        .frame(width: SlideToggleMetrics.size.width, height: SlideToggleMetrics.size.height, alignment: .topLeading)
        .animation(FrontPanelMotion.state(reduceMotion: reduceMotion), value: isOn)
    }
}

/// The even ring of recess around the track, shaded like the well every control sits in. The track is translucent,
/// so the cyan the lit legend spills is kept to this ring.
private struct SlideToggleRecess: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SlideToggleMetrics.radius)
                .strokeBorder(
                    LinearGradient(colors: [.black.opacity(0.4), .white.opacity(0.16)], startPoint: .top, endPoint: .bottom),
                    lineWidth: SlideToggleMetrics.ring
                )
            EllipticalGlow(stops: SlideToggleMetrics.ringGlowStops, radii: CGSize(width: 64, height: 38))
                .position(x: SlideToggleMetrics.size.width * 0.7, y: SlideToggleMetrics.size.height * 0.78)
                .mask {
                    RoundedRectangle(cornerRadius: SlideToggleMetrics.radius)
                        .strokeBorder(lineWidth: SlideToggleMetrics.ring)
                }
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: SlideToggleMetrics.size.width, height: SlideToggleMetrics.size.height)
    }
}

/// The translucent track, a touch darker than the panel around it, with the legends and the knob inside it.
private struct SlideToggleTrack: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: SlideToggleMetrics.trackRadius)
                .fill(LinearGradient(stops: SlideToggleMetrics.trackStops, startPoint: .top, endPoint: .bottom))
            SlideToggleTrackShade()
            EllipticalGlow(stops: SlideToggleMetrics.trackGlowStops, radii: CGSize(width: 34, height: 22))
                .position(x: 65, y: SlideToggleMetrics.legendCenter)
                .opacity(isOn ? 1 : 0)
            SlideToggleLegend(text: Text("On"), isLit: true)
                .position(x: 65.5, y: SlideToggleMetrics.legendCenter)
                .opacity(isOn ? 1 : 0)
            SlideToggleLegend(text: Text("Off"), isLit: false)
                .position(x: 30.5, y: SlideToggleMetrics.legendCenter)
                .opacity(isOn ? 0 : 1)
            SlideToggleKnob(isOn: isOn)
                .offset(x: SlideToggleMetrics.knobInset + (isOn ? 0 : SlideToggleMetrics.travel), y: SlideToggleMetrics.knobInset)
        }
        .frame(width: SlideToggleMetrics.trackSize.width, height: SlideToggleMetrics.trackSize.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: SlideToggleMetrics.trackRadius))
    }
}

/// The track's inset shade, deepest along its top edge and its right side. It lies over the track's translucent
/// shade and under the legends and the knob.
private struct SlideToggleTrackShade: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SlideToggleMetrics.trackRadius)
        ZStack {
            InsetShadow(shape: shape, color: .black.opacity(0.25), blur: 1, offset: CGSize(width: 0, height: 2))
            InsetShadow(shape: shape, color: .black.opacity(0.21), offset: CGSize(width: 0, height: -1))
            InsetShadow(shape: shape, color: .black.opacity(0.17), offset: CGSize(width: 1, height: 0))
            InsetShadow(shape: shape, color: .black.opacity(0.25), offset: CGSize(width: -1, height: 0))
        }
        .frame(width: SlideToggleMetrics.trackSize.width, height: SlideToggleMetrics.trackSize.height)
    }
}

/// A legend in the reference image's bold Helvetica: the lit ON glows cyan, and the OFF is a darker caption.
private struct SlideToggleLegend: View {
    let text: Text
    let isLit: Bool

    var body: some View {
        text
            .font(.custom("Helvetica-Bold", size: 19))
            .textCase(.uppercase)
            .foregroundStyle(isLit ? Color(hex: 0x00FFE6) : SlideToggleMetrics.offLegend)
            .shadow(color: FrontPanelPalette.cyan.opacity(isLit ? 0.5 : 0), radius: 1)
            .shadow(color: FrontPanelPalette.cyan.opacity(isLit ? 0.25 : 0), radius: 3.5)
            .lineLimit(1)
            .fixedSize()
    }
}

/// The round knob, lit from above, whose edge toward the lit legend picks up its cyan.
private struct SlideToggleKnob: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(isOn ? AnyShapeStyle(Self.face.shadow(Self.litEdge)) : AnyShapeStyle(Self.face))
            .overlay {
                Circle()
                    .inset(by: -0.5)
                    .stroke(Color.black.opacity(0.3), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 1.25, x: 1, y: 1.5)
            .frame(width: SlideToggleMetrics.knobDiameter, height: SlideToggleMetrics.knobDiameter)
    }
}

private extension SlideToggleKnob {
    /// The knob's face, lit from above and a little from the left.
    static var face: some ShapeStyle {
        LinearGradient(stops: SlideToggleMetrics.knobStops, startPoint: .top, endPoint: .bottom)
            .shadow(.inner(color: .white.opacity(0.95), radius: 0, y: 1))
            .shadow(.inner(color: .white.opacity(0.3), radius: 0, x: 1))
    }

    /// The cyan the edge toward the lit legend picks up. It comes and goes with the face's style, because a chained
    /// inner shadow in a fully transparent color turns the whole fill white in SwiftUI's renderer.
    static let litEdge = ShadowStyle.inner(color: FrontPanelPalette.cyan.opacity(0.55), radius: 0.5, x: -1.5)
}

/// A soft elliptical glow of the given radii, centered in its own frame.
private struct EllipticalGlow: View {
    let stops: [Gradient.Stop]
    let radii: CGSize

    var body: some View {
        RadialGradient(stops: stops, center: .center, startRadius: 0, endRadius: radii.width)
            .frame(width: 2 * radii.width, height: 2 * radii.width)
            .scaleEffect(x: 1, y: radii.height / radii.width)
            .frame(width: 2 * radii.width, height: 2 * radii.height)
            .allowsHitTesting(false)
    }
}

/// The reference image's measurements, which the toggle draws at three fifths of their size.
private enum SlideToggleMetrics {
    static let zoom: CGFloat = 0.6
    static let ring: CGFloat = 2.5
    static let trackSize = CGSize(width: 99, height: 41)
    static let size = CGSize(width: trackSize.width + 2 * ring, height: trackSize.height + 2 * ring)
    static let radius: CGFloat = 23
    static let trackRadius = trackSize.height / 2
    static let legendCenter = trackSize.height / 2
    static let knobInset: CGFloat = 3
    static let knobDiameter: CGFloat = 35
    /// How far the knob moves from on to off.
    static let travel: CGFloat = 58
    /// The caption's color with 35 percent black in it.
    static let offLegend = Color(mixing: FrontPanelPalette.captionShade, 0x000000, secondShare: 0.35)
    static let trackStops: [Gradient.Stop] = [
        .init(color: .black.opacity(0.18), location: 0),
        .init(color: .black.opacity(0.18), location: 0.06),
        .init(color: .black.opacity(0.1), location: 0.52),
        .init(color: .black.opacity(0.1), location: 0.95),
        .init(color: .black.opacity(0.09), location: 1),
    ]
    static let knobStops: [Gradient.Stop] = [
        .init(color: Color(hex: 0xA9A9A9), location: 0),
        .init(color: Color(hex: 0xB3B3B3), location: 0.12),
        .init(color: Color(hex: 0xDCDCDC), location: 0.88),
        .init(color: Color(hex: 0xE1E1E1), location: 1),
    ]
    static let ringGlowStops: [Gradient.Stop] = [
        .init(color: FrontPanelPalette.cyan.opacity(0.22), location: 0),
        .init(color: FrontPanelPalette.cyan.opacity(0.07), location: 0.55),
        .init(color: FrontPanelPalette.cyan.opacity(0), location: 1),
    ]
    static let trackGlowStops: [Gradient.Stop] = [
        .init(color: FrontPanelPalette.cyan.opacity(0.12), location: 0),
        .init(color: FrontPanelPalette.cyan.opacity(0.05), location: 0.6),
        .init(color: FrontPanelPalette.cyan.opacity(0), location: 1),
    ]
}
