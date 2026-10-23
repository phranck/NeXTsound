import NeXTsoundCore
import SwiftUI

/// A front panel slider with its value in a readout above it and its caption below it.
///
/// The cap is the kit's light knob stretched to a pill, riding in a dark track between two scales. Every fader has
/// the same size, so the readouts, the faders and the captions of a row line up across its panels. A caption wider
/// than the fader's column reaches past both of its sides without widening the column, so a module with one fader
/// keeps its share of the row.
struct PanelFader: View {
    /// What VoiceOver calls the fader.
    let label: LocalizedStringKey
    let caption: LocalizedStringKey
    let parameter: DSPParameter
    let unit: FaderUnit
    @Binding var value: Float
    /// What VoiceOver reads after the value, such as the share of full volume.
    var spokenDetail: String?

    var body: some View {
        VStack(spacing: PanelFaderMetrics.wrapSpacing) {
            PanelReadout(text: unit.readout(value), layout: PanelFaderMetrics.readoutLayout, alignment: .trailing)
                .accessibilityHidden(true)
            FaderControl(label: label, scale: FaderScale(parameter: parameter), unit: unit, value: $value, spokenDetail: spokenDetail)
            ControlCaption(caption: Text(caption))
                .frame(width: Self.columnWidth)
                .accessibilityHidden(true)
        }
    }
}

extension PanelFader {
    /// The width of a fader's column, the width of its readout, which a caption of several lines under it breaks at.
    static var columnWidth: CGFloat {
        PanelFaderMetrics.readoutLayout.size.width + 2 * FrontPanelLayout.frameWidth
    }
}

/// The fader's track, scales and cap, and what it does with the pointer, the keyboard and VoiceOver.
///
/// A drag or a click anywhere in the track sets the value with the cap's center under the pointer, the way a console
/// fader works. The keyboard steps the cap by a share of the travel, so a step feels the same on a logarithmic scale
/// as on a linear one. A drag gives the fader the keyboard's focus, and the fader shows no ring while it has it. The
/// cap travels to a value set from elsewhere and follows a drag without delay.
private struct FaderControl: View {
    let label: LocalizedStringKey
    let scale: FaderScale
    let unit: FaderUnit
    @Binding var value: Float
    let spokenDetail: String?
    @State private var isDragging = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            FaderTicks()
            FaderTrack()
            FaderCap()
                .offset(y: (1 - position) * PanelFaderMetrics.travel)
                .animation(isDragging ? nil : FrontPanelMotion.state(reduceMotion: reduceMotion), value: position)
        }
        .frame(width: PanelFaderMetrics.width, height: PanelFaderMetrics.height)
        .contentShape(Rectangle())
        .gesture(drag)
        .panelFocus($isFocused)
        .onKeyPress(keys: PanelFaderMetrics.handledKeys) { press in
            handle(press.key)
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setPosition(position + PanelFaderMetrics.step)
            case .decrement: setPosition(position - PanelFaderMetrics.step)
            @unknown default: break
            }
        }
    }
}

private extension FaderControl {
    var position: Double {
        scale.position(for: value)
    }

    var spokenValue: String {
        [unit.spoken(value), spokenDetail].compactMap(\.self).joined(separator: ", ")
    }

    /// Holds the cap by its center, so the cap stays under the pointer along the whole track.
    var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                isDragging = true
                isFocused = true
                let capCenter = drag.location.y - PanelFaderMetrics.capHeight / 2
                setPosition(1 - Double(capCenter / PanelFaderMetrics.travel))
            }
            .onEnded { _ in
                isDragging = false
            }
    }

    func handle(_ key: KeyEquivalent) -> KeyPress.Result {
        if let step = PanelFaderMetrics.keySteps[key] {
            setPosition(position + step)
        } else if let end = PanelFaderMetrics.keyEnds[key] {
            setPosition(end)
        } else {
            return .ignored
        }
        return .handled
    }

    func setPosition(_ newPosition: Double) {
        let newValue = scale.value(at: newPosition)
        if newValue != value {
            value = newValue
        }
    }
}

/// The scale beside the track on both sides, a tick at both ends of the cap's travel and an even count of intervals
/// between them, so one tick marks the middle.
private struct FaderTicks: View {
    var body: some View {
        Canvas { context, size in
            let metrics = PanelFaderMetrics.self
            var ticks = Path()
            for index in 0 ... metrics.tickIntervals {
                let top = metrics.capHeight / 2 + CGFloat(index) * metrics.travel / CGFloat(metrics.tickIntervals)
                ticks.addRect(CGRect(x: 0, y: top, width: metrics.tickLength, height: 1))
                ticks.addRect(CGRect(x: size.width - metrics.tickLength, y: top, width: metrics.tickLength, height: 1))
            }
            context.fill(ticks, with: .color(metrics.tickColor))
        }
        .accessibilityHidden(true)
    }
}

/// The groove the cap rides in, shaded from its top edge and ringed in the kit's outline.
private struct FaderTrack: View {
    var body: some View {
        Capsule()
            .fill(
                LinearGradient(colors: [Color(hex: 0x1B1B1B), Color(hex: 0x2B2B2B)], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: .black.opacity(0.8), radius: 1.5, y: 2))
            )
            .overlay {
                Capsule()
                    .inset(by: -0.5)
                    .stroke(FrontPanelPalette.outline, lineWidth: 1)
            }
            .frame(width: PanelFaderMetrics.trackWidth)
    }
}

/// The light cap, lit from above, with the grip line that marks the value across its middle.
private struct FaderCap: View {
    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0xECECEC), location: 0),
                        .init(color: Color(hex: 0xC8C8C8), location: 0.55),
                        .init(color: Color(hex: 0xA6A6A6), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .shadow(.inner(color: .white.opacity(0.75), radius: 0, y: 1))
            )
            .overlay {
                Capsule()
                    .inset(by: -0.5)
                    .stroke(FrontPanelPalette.outline, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                FaderGripLine()
            }
            .shadow(color: .black.opacity(0.55), radius: 1.5, y: 2)
            .frame(width: PanelFaderMetrics.capWidth, height: PanelFaderMetrics.capHeight)
    }
}

/// An engraved line with a highlight under it, ending five points short of the cap's sides.
private struct FaderGripLine: View {
    var body: some View {
        VStack(spacing: 0) {
            FrontPanelPalette.engraving
                .frame(height: 1)
            Color.white.opacity(0.6)
                .frame(height: 1)
        }
        .padding(.horizontal, 5)
        .offset(y: PanelFaderMetrics.capHeight / 2 - 1)
    }
}

/// A fader's measurements and keys, from the mockup.
private enum PanelFaderMetrics {
    static let width: CGFloat = 30
    static let height: CGFloat = 108
    static let capWidth = width
    static let capHeight: CGFloat = 14
    static let trackWidth: CGFloat = 6
    /// The distance the cap's center travels from the top of its range to the bottom.
    static let travel = height - capHeight
    /// The space between a readout, its fader and its caption.
    static let wrapSpacing: CGFloat = 5
    /// A readout of five character cells, right-justified like a numeric display.
    static let readoutLayout = DotMatrixLinesLayout(cells: 5)
    static let tickGap: CGFloat = 2
    static let tickLength = (capWidth - trackWidth) / 2 - tickGap
    /// About ten points between ticks, in an even count of intervals.
    static let tickIntervals = 2 * max(1, Int((travel / 20).rounded()))
    static let tickColor = Color(red: 207 / 255, green: 203 / 255, blue: 189 / 255).opacity(0.35)
    /// One arrow key's step, a share of the travel.
    static let step = 0.01
    /// One page key's step.
    static let page = 0.1
    static let keySteps: [KeyEquivalent: Double] = [
        .upArrow: step,
        .rightArrow: step,
        .downArrow: -step,
        .leftArrow: -step,
        .pageUp: page,
        .pageDown: -page,
    ]
    /// Home goes to the lowest value and End to the highest.
    static let keyEnds: [KeyEquivalent: Double] = [.home: 0, .end: 1]
    static let handledKeys = Set(keySteps.keys).union(keyEnds.keys)
}
