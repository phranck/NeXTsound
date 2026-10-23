import NeXTsoundCore
import SwiftUI

/// Writes the front panel's edits into the selected profile through the model's edit path.
///
/// Each edit advances the profile's revision, registers its undo and plays on a connected SoundBox.
@MainActor
struct FrontPanelEditor {
    let model: WorkbenchModel
    let undoManager: UndoManager?
}

extension FrontPanelEditor {
    /// The selected profile's settings as they stand.
    var settings: DSPSettings {
        model.profile.settings
    }

    /// A binding to one of the selected profile's settings.
    func binding<Value: Sendable>(_ keyPath: WritableKeyPath<DSPSettings, Value> & Sendable) -> Binding<Value> {
        Binding {
            model.profile.settings[keyPath: keyPath]
        } set: { newValue in
            edit { $0[keyPath: keyPath] = newValue }
        }
    }

    /// A binding to one setting of one of the selected profile's bands.
    func binding<Value: Sendable>(band: Int, _ keyPath: WritableKeyPath<EQBand, Value> & Sendable) -> Binding<Value> {
        Binding {
            model.profile.settings.bands[band][keyPath: keyPath]
        } set: { newValue in
            edit { $0.bands[band][keyPath: keyPath] = newValue }
        }
    }

    /// Puts a band back to how a new profile has it.
    func resetBand(_ band: Int) {
        edit { $0.bands[band] = DSPSettings.defaultBand(at: band) }
    }
}

private extension FrontPanelEditor {
    func edit(_ change: (inout DSPSettings) -> Void) {
        var proposed = model.profile
        change(&proposed.settings)
        model.updateProfile(proposed, undoManager: undoManager)
    }
}

/// The row of panels under the display: the band panel, the High-Pass, Output and Sample-Peak Limiter modules, and
/// at the right end the display color keys over the key that opens the Library window.
///
/// Every panel is as tall as the tallest, so the readouts, the slider captions and the captions along the bottom each
/// run on one line across the row. The modules with one slider take two thirds of the width the limiter takes for its
/// two.
struct FrontPanelControlRow: View {
    let editor: FrontPanelEditor
    let boardButtons: FrontPanelBoardButtons
    @Binding var selectedBand: Int
    @Binding var theme: PhosphorTheme
    @Binding var isLibraryOpen: Bool

    var body: some View {
        HStack(alignment: .top, spacing: PanelRowMetrics.panelSpacing) {
            BandPanel(editor: editor, selectedBand: $selectedBand, theme: theme)
            SharedWidthRow(spacing: PanelRowMetrics.panelSpacing) {
                HighPassModule(editor: editor, theme: theme)
                    .rowWidthShare(PanelRowMetrics.oneSliderModuleShare)
                OutputModule(editor: editor, theme: theme)
                    .rowWidthShare(PanelRowMetrics.oneSliderModuleShare)
                LimiterModule(editor: editor, buttons: boardButtons, theme: theme)
            }
            ColorAndLibraryColumn(theme: $theme, isLibraryOpen: $isLibraryOpen)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(PanelRowMetrics.margin)
    }
}

/// The SoundBox's two buttons on the panel, and whether the SAVE LED is lit.
struct FrontPanelBoardButtons {
    let saveLEDIsLit: Bool
    let save: () -> Void
    let flash: () -> Void
}

/// The band panel: one set of sliders for the band its keys select, because five full sets never fit side by side
/// at a size where their readouts stay legible. The curve sums all five bands, whichever one is selected.
private struct BandPanel: View {
    let editor: FrontPanelEditor
    @Binding var selectedBand: Int
    let theme: PhosphorTheme

    var body: some View {
        VStack(spacing: PanelRowMetrics.stackSpacing) {
            PanelTitle(title: "EQ Band \(selectedBand + 1) of \(DSPSettings.bandCount)")
            SpreadRow(minimumSpacing: PanelRowMetrics.controlSpacing) {
                PanelFader(
                    label: "Band frequency",
                    caption: "Freq",
                    parameter: .bandFrequency,
                    unit: .hertz,
                    value: editor.binding(band: selectedBand, \.frequencyHz),
                    theme: theme
                )
                PanelFader(
                    label: "Band gain",
                    caption: "Gain",
                    parameter: .bandGain,
                    unit: .decibels,
                    value: editor.binding(band: selectedBand, \.gainDb),
                    theme: theme
                )
                PanelFader(
                    label: "Band quality",
                    caption: "Quality",
                    parameter: .bandQuality,
                    unit: .quality,
                    value: editor.binding(band: selectedBand, \.quality),
                    theme: theme
                )
            }
            KeyBank("Band select", selection: $selectedBand, keys: Self.bandKeys) { band in
                BandCommandsMenu(band: FrontPanelBand(editor: editor, index: band))
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .panelPadding()
    }
}

private extension BandPanel {
    static var bandKeys: [KeyBankKey<Int>] {
        (0 ..< DSPSettings.bandCount).map { band in
            KeyBankKey(value: band, caption: Text(verbatim: "\(band + 1)"), name: Text("Band \(band + 1)"))
        }
    }
}

private struct HighPassModule: View {
    let editor: FrontPanelEditor
    let theme: PhosphorTheme

    var body: some View {
        PanelModule(title: "High-pass") {
            ControlColumn {
                PanelFader(
                    label: "High-pass cutoff",
                    caption: "Cutoff",
                    parameter: .highPassFrequency,
                    unit: .hertz,
                    value: editor.binding(\.highPassHz),
                    theme: theme
                )
            } bottom: {
                LabeledToggle(label: "High-pass enabled", caption: "Enabled", isOn: editor.binding(\.highPassEnabled))
            }
        }
    }
}

/// The output module. VoiceOver reads the volume with its share of full volume, because the decibels alone say little
/// before the scale is learned.
private struct OutputModule: View {
    let editor: FrontPanelEditor
    let theme: PhosphorTheme

    var body: some View {
        PanelModule(title: "Output") {
            ControlColumn {
                PanelFader(
                    label: "Master Volume",
                    caption: "Master Volume",
                    parameter: .attenuation,
                    unit: .decibels,
                    value: editor.binding(\.attenuationDb),
                    theme: theme,
                    spokenDetail: editor.settings.shareOfFullVolumeText
                )
            } bottom: {
                LabeledToggle(label: "Muted", caption: "Muted", isOn: editor.binding(\.isMuted))
            }
        }
    }
}

private struct LimiterModule: View {
    let editor: FrontPanelEditor
    let buttons: FrontPanelBoardButtons
    let theme: PhosphorTheme

    var body: some View {
        PanelModule(title: "Sample-peak limiter") {
            ControlColumn {
                PanelFader(
                    label: "Limiter ceiling",
                    caption: "Ceiling",
                    parameter: .limiterThreshold,
                    unit: .decibels,
                    value: editor.binding(\.limiterThresholdDb),
                    theme: theme
                )
            } bottom: {
                VStack(spacing: FrontPanelLayout.captionSpacing) {
                    PanelLED(isLit: buttons.saveLEDIsLit, confirms: true)
                    PanelPushButton(label: "Save to SoundBox", kind: .save, action: buttons.save)
                    ControlCaption(caption: Text("Save to SoundBox"), wrapWidth: PanelFader.columnWidth)
                        .accessibilityHidden(true)
                }
            }
            ControlColumn {
                PanelFader(
                    label: "Limiter release",
                    caption: "Release",
                    parameter: .limiterRelease,
                    unit: .milliseconds,
                    value: editor.binding(\.limiterReleaseMs),
                    theme: theme
                )
            } bottom: {
                VStack(spacing: FrontPanelLayout.captionSpacing) {
                    PanelPushButton(label: "Flash Firmware", kind: .flash, action: buttons.flash)
                    ControlCaption(caption: Text("Flash Firmware"), wrapWidth: PanelFader.columnWidth)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// The column at the right end of the row: the display color keys at its top, whose LEDs stand on the middle of the
/// panel titles' line, and the key that opens the Library window at its bottom, whose LED, face and caption line up
/// with the band keys'.
private struct ColorAndLibraryColumn: View {
    @Binding var theme: PhosphorTheme
    @Binding var isLibraryOpen: Bool

    var body: some View {
        VStack(spacing: 0) {
            KeyBank("Display color", selection: $theme, keys: Self.themeKeys)
            LatchingKey(caption: "Library", isOn: $isLibraryOpen)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(PanelRowMetrics.colorColumnPadding)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private extension ColorAndLibraryColumn {
    static var themeKeys: [KeyBankKey<PhosphorTheme>] {
        PhosphorTheme.allCases.map { theme in
            KeyBankKey(value: theme, caption: Text(theme.name), name: Text(theme.name))
        }
    }
}

private extension PhosphorTheme {
    var name: LocalizedStringKey {
        switch self {
        case .blue: "Blue"
        case .white: "White"
        case .amber: "Amber"
        }
    }
}

/// A module: its title over a row of control columns that fills the panel's height.
private struct PanelModule<Columns: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let columns: Columns

    var body: some View {
        VStack(spacing: PanelRowMetrics.stackSpacing) {
            PanelTitle(title: title)
            SpreadRow(minimumSpacing: PanelRowMetrics.controlSpacing) {
                columns
            }
            .frame(maxHeight: .infinity)
        }
        .panelPadding()
    }
}

/// A slider at the top of a module's column and the control that belongs with it at the bottom, with its caption on
/// the panels' caption line.
private struct ControlColumn<Top: View, Bottom: View>: View {
    @ViewBuilder let top: Top
    @ViewBuilder let bottom: Bottom

    var body: some View {
        VStack(spacing: PanelRowMetrics.stackSpacing) {
            top
            bottom
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// A slide toggle with its caption under it. The toggle stands in a fader's column, and a caption wider than the
/// column reaches past both of its sides without widening it.
private struct LabeledToggle: View {
    let label: LocalizedStringKey
    let caption: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        VStack(spacing: FrontPanelLayout.captionSpacing) {
            SlideToggle(label: label, isOn: $isOn)
            ControlCaption(caption: Text(caption))
                .frame(width: PanelFader.columnWidth)
                .accessibilityHidden(true)
        }
    }
}

private extension View {
    /// The padding every panel shares, which puts every caption along the bottom on one line. A panel takes the row's
    /// full height.
    func panelPadding() -> some View {
        padding(PanelRowMetrics.panelPadding)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The row's measurements, from the mockup.
private enum PanelRowMetrics {
    static let margin = EdgeInsets(top: 0, leading: 24, bottom: 18, trailing: 24)
    static let panelSpacing: CGFloat = 24
    /// The share a module with one slider takes of the width the limiter takes for its two.
    static let oneSliderModuleShare: CGFloat = 2 / 3
    static let panelPadding = EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
    /// The space between a panel's title, its controls and its lower controls.
    static let stackSpacing: CGFloat = 14
    /// The least space between two controls side by side.
    static let controlSpacing: CGFloat = 6
    /// The right end column's padding, which centers the display color keys' LEDs on the titles' line.
    static let colorColumnPadding = EdgeInsets(
        top: panelPadding.top + (FrontPanelType.lineHeight - PanelLED.size) / 2,
        leading: panelPadding.leading,
        bottom: panelPadding.bottom,
        trailing: panelPadding.trailing
    )
}
