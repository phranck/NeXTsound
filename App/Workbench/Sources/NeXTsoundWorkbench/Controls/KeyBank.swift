import SwiftUI

/// One key of a key bank: the value it selects, its caption under the bank, and its name for VoiceOver.
struct KeyBankKey<Value: Hashable>: Identifiable {
    let value: Value
    let caption: Text
    let name: Text

    var id: Value {
        value
    }
}

/// A row of latching keys in a dark frame, of which exactly one is down, the way a tape deck's keys hold each other.
///
/// The key that is down sits lower than its neighbors under a little shade, and the LED above it lights, while its
/// plastic keeps its color as a real key's does. The bank is one stop for the keyboard and shows no ring while it has
/// the focus. The arrow keys move the selection, and VoiceOver reads the bank as a group of radio buttons.
struct KeyBank<Value: Hashable, KeyMenu: View>: View {
    let label: LocalizedStringKey
    @Binding var selection: Value
    let keys: [KeyBankKey<Value>]
    /// The context menu of each key, for the key's own value.
    let keyMenu: (Value) -> KeyMenu
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: KeyBankMetrics.captionSpacing) {
            HStack(alignment: .top, spacing: KeyBankMetrics.keyGap) {
                ForEach(keys) { key in
                    BankKey(isDown: key.value == selection) {
                        selection = key.value
                        isFocused = true
                    }
                    .contextMenu {
                        keyMenu(key.value)
                    }
                }
            }
            .padding(KeyBankMetrics.framePadding)
            .background(KeyBankFrame())
            HStack(spacing: KeyBankMetrics.keyGap) {
                ForEach(keys) { key in
                    ControlCaption(caption: key.caption)
                        .frame(width: KeyBankMetrics.keyWidth)
                }
            }
            .padding(.horizontal, KeyBankMetrics.framePadding)
            .accessibilityHidden(true)
        }
        .padding(.top, KeyBankMetrics.ledLift + PanelLED.size)
        .panelFocus($isFocused)
        .onKeyPress(keys: Set(KeyBankNavigation.steps.keys)) { press in
            moveSelection(by: KeyBankNavigation.steps[press.key] ?? 0)
            return .handled
        }
        .accessibilityRepresentation {
            Picker(label, selection: $selection) {
                ForEach(keys) { key in
                    key.name.tag(key.value)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }

    /// - Parameters:
    ///   - label: What VoiceOver calls the bank.
    ///   - selection: The value of the key that is down.
    ///   - keys: The keys from left to right.
    ///   - keyMenu: The context menu of each key.
    init(
        _ label: LocalizedStringKey,
        selection: Binding<Value>,
        keys: [KeyBankKey<Value>],
        @ViewBuilder keyMenu: @escaping (Value) -> KeyMenu
    ) {
        self.label = label
        _selection = selection
        self.keys = keys
        self.keyMenu = keyMenu
    }
}

extension KeyBank where KeyMenu == EmptyView {
    /// A bank whose keys have no context menu.
    init(_ label: LocalizedStringKey, selection: Binding<Value>, keys: [KeyBankKey<Value>]) {
        self.init(label, selection: selection, keys: keys) { _ in EmptyView() }
    }
}

private extension KeyBank {
    func moveSelection(by step: Int) {
        guard let index = keys.firstIndex(where: { $0.value == selection }) else {
            return
        }
        selection = keys[KeyBankNavigation.index(after: index, step: step, count: keys.count)].value
    }
}

/// Where the arrow keys move a key bank's selection: one key on, and from either end around to the other.
enum KeyBankNavigation {
    static let steps: [KeyEquivalent: Int] = [.rightArrow: 1, .downArrow: 1, .leftArrow: -1, .upArrow: -1]

    static func index(after index: Int, step: Int, count: Int) -> Int {
        guard count > 0 else {
            return 0
        }
        return ((index + step) % count + count) % count
    }
}

/// One momentary key: its action, its caption, its name for VoiceOver, and whether it can be pressed.
struct MomentaryKey: Identifiable {
    let id: String
    /// The caption in its localized form, which a caption under a single key is measured from.
    let caption: String
    let name: Text
    var isEnabled = true
    let action: () -> Void
}

/// A row of momentary keys in a key bank's frame, with each key's caption under it.
///
/// Each key springs back when it is let go and starts an action of its own, so the bank has no LEDs, and each is a
/// stop of its own for the keyboard. Every key names its action in a whole word, which stays clear of its neighbor's
/// only without the captions' usual letter spacing.
struct MomentaryKeyBank: View {
    let keys: [MomentaryKey]

    var body: some View {
        VStack(spacing: KeyBankMetrics.captionSpacing) {
            MomentaryKeyFrame(keys: keys)
            HStack(spacing: KeyBankMetrics.keyGap) {
                ForEach(keys) { key in
                    ControlCaption(caption: Text(verbatim: key.caption), tracking: 0)
                        .frame(width: KeyBankMetrics.keyWidth)
                }
            }
            .padding(.horizontal, KeyBankMetrics.framePadding)
            .accessibilityHidden(true)
        }
    }
}

extension MomentaryKeyBank {
    /// The width of a bank of `keyCount` keys, its frame included.
    nonisolated static func width(keyCount: Int) -> CGFloat {
        let keys = KeyBankMetrics.keyWidth * CGFloat(keyCount)
        return keys + KeyBankMetrics.keyGap * CGFloat(max(keyCount - 1, 0)) + 2 * KeyBankMetrics.framePadding
    }
}

/// A single momentary key in its frame, with its caption under it broken between its words, so the two take no more
/// width than the frame or the caption's widest word.
struct LabeledMomentaryKey: View {
    let key: MomentaryKey

    var body: some View {
        VStack(spacing: FrontPanelLayout.captionSpacing) {
            MomentaryKeyFrame(keys: [key])
            ControlCaption(wrappingToWidestWord: key.caption)
                .accessibilityHidden(true)
        }
    }
}

/// Momentary keys side by side in a key bank's frame.
private struct MomentaryKeyFrame: View {
    let keys: [MomentaryKey]

    var body: some View {
        HStack(alignment: .top, spacing: KeyBankMetrics.keyGap) {
            ForEach(keys) { key in
                MomentaryBankKey(key: key)
            }
        }
        .padding(KeyBankMetrics.framePadding)
        .background(KeyBankFrame())
    }
}

/// One momentary key, which takes the keyboard's focus without showing a ring.
private struct MomentaryBankKey: View {
    let key: MomentaryKey

    var body: some View {
        Button(action: key.action) {
            EmptyView()
        }
        .buttonStyle(BankKeyStyle(kind: .push, isDown: false))
        .disabled(!key.isEnabled)
        .focusEffectDisabled()
        .accessibilityLabel(key.name)
    }
}

/// One square key with the LED that sits above the bank's frame over it.
private struct BankKey: View {
    let isDown: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EmptyView()
        }
        .buttonStyle(BankKeyStyle(kind: .radio, isDown: isDown))
        .focusable(false)
        .keyLED(isLit: isDown)
    }
}

/// A single latching key in a key bank's frame, with its LED above the frame and its caption under it, laid out as a
/// key bank lays out each of its keys.
///
/// A press latches the key down and lights its LED, and the next press releases it. The key takes the keyboard's
/// focus without showing a ring, and VoiceOver reads it as a switch.
struct LatchingKey: View {
    let caption: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        VStack(spacing: KeyBankMetrics.captionSpacing) {
            Button {
                isOn.toggle()
            } label: {
                EmptyView()
            }
            .buttonStyle(BankKeyStyle(kind: .push, isDown: isOn))
            .focusEffectDisabled()
            .keyLED(isLit: isOn)
            .padding(KeyBankMetrics.framePadding)
            .background(KeyBankFrame())
            ControlCaption(caption: Text(caption))
                .frame(width: KeyBankMetrics.keyWidth)
                .padding(.horizontal, KeyBankMetrics.framePadding)
                .accessibilityHidden(true)
        }
        .padding(.top, KeyBankMetrics.ledLift + PanelLED.size)
        .accessibilityRepresentation {
            Toggle(caption, isOn: $isOn)
        }
    }
}

private extension View {
    /// Puts the LED that sits above a key bank's frame over a key in the frame.
    func keyLED(isLit: Bool) -> some View {
        overlay(alignment: .top) {
            PanelLED(isLit: isLit)
                .offset(y: -(KeyBankMetrics.framePadding + KeyBankMetrics.ledLift + PanelLED.size))
        }
    }
}

/// What a key does, which decides its color. A radio key, one of a bank of which one is down, keeps the kit's gray. A
/// push key, which starts an action or latches, takes the yellow of the header's stripes.
private enum KeyKind {
    case radio
    case push
}

private extension KeyKind {
    /// A shade of the kit's gray key in this kind's color. A push key's yellow is as much darker or lighter as the gray
    /// shade is against the face's top shade: mixed with black below it and with white above it.
    func color(forKitShade shade: UInt32) -> Color {
        switch self {
        case .radio:
            return Color(hex: shade)
        case .push:
            let gray = Double(shade & 0xFF)
            let reference = Double(KeyBankMetrics.faceTop & 0xFF)
            if gray <= reference {
                return Color(mixing: 0x000000, FrontPanelPalette.stripeYellow, secondShare: gray / reference)
            }
            return Color(mixing: FrontPanelPalette.stripeYellow, 0xFFFFFF, secondShare: (gray - reference) / (0xFF - reference))
        }
    }
}

/// A key that sinks while it is down or pressed, in its kind's color.
private struct BankKeyStyle: ButtonStyle {
    let kind: KeyKind
    let isDown: Bool

    func makeBody(configuration: Configuration) -> some View {
        KeyFace(kind: kind, isLowered: isDown || configuration.isPressed)
    }
}

/// The key's face in its kind's color, lit from above so it darkens toward the bottom, with its dish and the shade of
/// a lowered key.
private struct KeyFace: View {
    let kind: KeyKind
    let isLowered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: KeyBankMetrics.keyRadius)
            .fill(
                LinearGradient(
                    colors: [kind.color(forKitShade: KeyBankMetrics.faceTop), kind.color(forKitShade: KeyBankMetrics.faceBottom)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .shadow(.inner(color: .white.opacity(0.3), radius: 0, y: 1))
                .shadow(.inner(color: .white.opacity(0.08), radius: 0, y: -1))
                .shadow(.inner(color: .white.opacity(0.06), radius: 0, x: 1))
                .shadow(.inner(color: .white.opacity(0.08), radius: 0, x: -1))
            )
            .overlay {
                KeyDish(kind: kind)
            }
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: KeyBankMetrics.keyRadius)
                        .fill(Color.black.opacity(0.1))
                    InsetShadow(
                        shape: RoundedRectangle(cornerRadius: KeyBankMetrics.keyRadius),
                        color: .black.opacity(0.5),
                        blur: 6,
                        offset: CGSize(width: 0, height: 3)
                    )
                }
                .opacity(isLowered ? 1 : 0)
                .animation(FrontPanelMotion.state(reduceMotion: reduceMotion), value: isLowered)
            }
            .frame(width: KeyBankMetrics.keyWidth, height: KeyBankMetrics.keyHeight)
            .contentShape(Rectangle())
    }
}

/// The key's dish, lit from above and a little from the left, with a soft highlight on its lower left wall, which
/// faces the light. Gradient and spot are fitted to the kit's dish.
private struct KeyDish: View {
    let kind: KeyKind

    var body: some View {
        Circle()
            .fill(LinearGradient(
                stops: KeyBankMetrics.dishStops(for: kind),
                startPoint: KeyBankMetrics.dishStart,
                endPoint: KeyBankMetrics.dishEnd
            ))
            .overlay {
                Circle()
                    .fill(RadialGradient(
                        stops: KeyBankMetrics.dishHighlightStops,
                        center: UnitPoint(x: 0.269, y: 0.885),
                        startRadius: 0,
                        endRadius: KeyBankMetrics.dishDiameter * 0.606
                    ))
            }
            .frame(width: KeyBankMetrics.dishDiameter, height: KeyBankMetrics.dishDiameter)
    }
}

/// The dark frame the keys sit in. Its corners run parallel to the keys', so its radius is theirs plus its padding.
private struct KeyBankFrame: View {
    var body: some View {
        RoundedRectangle(cornerRadius: KeyBankMetrics.frameRadius)
            .fill(
                LinearGradient(colors: [Color(hex: 0x1B1B1B), Color(hex: 0x060606)], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: .black.opacity(0.8), radius: 1, y: 1))
            )
            .frameHighlight(cornerRadius: KeyBankMetrics.frameRadius, opacity: 0.1)
    }
}

/// A key bank's measurements.
private enum KeyBankMetrics {
    /// The kit's key, which a key's height, corners and dish take their measure from.
    static let kitKeySize: CGFloat = 40
    /// A key is 6 points wider than the kit's, so the six-letter captions of neighboring momentary keys stay apart.
    static let keyWidth = kitKeySize + 6
    /// The kit's keys are a hair taller than wide.
    static let keyHeight = kitKeySize * 61 / 60
    static let keyRadius = kitKeySize * 0.133
    static let keyGap: CGFloat = 2
    static let framePadding: CGFloat = 2
    static let frameRadius = keyRadius + framePadding
    /// The space between the frame's top and the LEDs' bottom.
    static let ledLift: CGFloat = 5
    static let captionSpacing: CGFloat = 6
    static let dishDiameter = kitKeySize * 0.87
    /// The dish's shades in steps of a tenth along its gradient.
    static let dishShades: [UInt32] = [
        0x828282,
        0x868686,
        0x8B8B8B,
        0x8F8F8F,
        0x959595,
        0x9B9B9B,
        0xA3A3A3,
        0xAAAAAA,
        0xB0B0B0,
        0xB5B5B5,
        0xBABABA,
    ]
    /// The top and the bottom of the kit's face, which darkens toward its bottom as light from above does.
    static let faceTop: UInt32 = 0x9D9D9D
    static let faceBottom: UInt32 = 0x909090

    /// The dish's gradient stops in a kind's color.
    static func dishStops(for kind: KeyKind) -> [Gradient.Stop] {
        dishShades.enumerated().map { index, shade in
            Gradient.Stop(color: kind.color(forKitShade: shade), location: Double(index) / Double(dishShades.count - 1))
        }
    }

    static let dishHighlightStops: [Gradient.Stop] = [
        .init(color: .white.opacity(0.3), location: 0),
        .init(color: .white.opacity(0.182), location: 0.333),
        .init(color: .white.opacity(0.098), location: 0.5),
        .init(color: .white.opacity(0.04), location: 0.667),
        .init(color: .white.opacity(0.013), location: 0.833),
        .init(color: .white.opacity(0), location: 1),
    ]

    /// The ends of the 200 degree gradient across the dish, which runs from its upper right to its lower left.
    static let dishStart = gradientPoint(degrees: 200, end: -1)
    static let dishEnd = gradientPoint(degrees: 200, end: 1)

    /// One end of a CSS gradient line at `degrees` across a square, where `end` is -1 for the start and 1 for the
    /// end. The line runs through the center and is long enough to reach the square's far corners.
    static func gradientPoint(degrees: Double, end: Double) -> UnitPoint {
        let radians = degrees * .pi / 180
        let halfLength = (abs(sin(radians)) + abs(cos(radians))) / 2
        return UnitPoint(x: 0.5 + end * sin(radians) * halfLength, y: 0.5 - end * cos(radians) * halfLength)
    }
}
