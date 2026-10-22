import NeXTsoundCore
import SwiftUI

/// The Library panel's content: the profiles with their keys, the selected profile's speaker, and the connected
/// SoundBox's name, in one column as wide as the profile keys.
///
/// The panel's title bar is hidden like the front panel's, so the metal reaches under it, and the panel sets its
/// title in the bar itself. Its readouts take the display color that the front panel's keys choose.
public struct LibraryPanel: View {
    private let model: WorkbenchModel
    private let driverLibrary: DriverLibraryModel
    @AppStorage(PhosphorTheme.storageKey) private var theme = PhosphorTheme.blue
    @Environment(\.undoManager) private var undoManager

    public var body: some View {
        WholePointFrame {
            VStack(alignment: .leading, spacing: LibraryPanelLayout.sectionSpacing) {
                ProfilesSection(editor: editor, theme: theme)
                SpeakerSection(editor: editor, drivers: driverLibrary.drivers, theme: theme)
                SoundBoxSection(model: model, theme: theme)
            }
            .frame(width: LibraryPanelLayout.contentWidth)
            .padding(LibraryPanelLayout.padding)
            .fixedSize()
        }
        .background {
            BrushedMetal()
        }
        .overlay(alignment: .top) {
            PanelWindowTitle(title: WorkbenchLayout.libraryWindowTitle)
        }
        .ignoresSafeArea()
        .focusedSceneValue(\.libraryEditor, editor)
    }

    /// - Parameters:
    ///   - model: The workbench's model, whose library the panel shows and edits.
    ///   - driverLibrary: The driver models the speaker menu offers.
    public init(model: WorkbenchModel, driverLibrary: DriverLibraryModel) {
        _ = FrontPanelFonts.registration
        self.model = model
        self.driverLibrary = driverLibrary
    }
}

private extension LibraryPanel {
    var editor: LibraryEditor {
        LibraryEditor(model: model, undoManager: undoManager)
    }
}

/// The Library panel's measurements, from the mockup.
enum LibraryPanelLayout {
    /// The panel's title bar, which the metal reaches under.
    static let titleBarHeight: CGFloat = 24
    static let titleSize: CGFloat = 11
    /// The width of the four profile keys, which every readout fills.
    static let contentWidth = MomentaryKeyBank.width(keyCount: 4)
    static let padding = EdgeInsets(top: titleBarHeight + 12, leading: 18, bottom: 20, trailing: 18)
    static let sectionSpacing: CGFloat = 22
    /// The space between a section's title and its rows, and between the rows.
    static let rowSpacing: CGFloat = 12
    /// The space between an indicator's LED and its caption.
    static let indicatorSpacing: CGFloat = 8
}

/// The panel's title, centered in its title bar in the system font, as the mockup sets it.
private struct PanelWindowTitle: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: LibraryPanelLayout.titleSize))
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: LibraryPanelLayout.titleBarHeight)
            .accessibilityHidden(true)
    }
}

/// A section of the panel: its title over its rows.
private struct LibrarySection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: LibraryPanelLayout.rowSpacing) {
            PanelTitle(title: title)
            content
        }
    }
}

/// A section's last row: an indicator at the left and the section's key at the right, both ending on one line.
private struct SectionRow<Indicator: View, Key: View>: View {
    @ViewBuilder let indicator: Indicator
    @ViewBuilder let key: Key

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            indicator
            Spacer(minLength: LibraryPanelLayout.rowSpacing)
            key
        }
    }
}

/// An LED with its caption beside it, which shows a state rather than starting an action.
private struct PanelIndicator: View {
    let caption: String
    let isLit: Bool
    let color: PanelLEDColor
    /// What VoiceOver reads for the indicator, which names the state the LED shows.
    let spokenText: String

    var body: some View {
        HStack(spacing: LibraryPanelLayout.indicatorSpacing) {
            PanelLED(isLit: isLit, color: color)
            ControlCaption(wrappingToWidestWord: caption, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenText))
    }
}

/// The profiles: the list over the keys that add, delete, import and export one.
private struct ProfilesSection: View {
    let editor: LibraryEditor
    let theme: PhosphorTheme

    var body: some View {
        LibrarySection(title: "Profiles") {
            ProfileList(editor: editor, theme: theme)
            MomentaryKeyBank(keys: keys)
        }
    }
}

private extension ProfilesSection {
    /// The delete key's caption. It has a key of its own, because the catalog's Delete names a button, and German
    /// labels a delete key Entf.
    static var deleteCaption: String {
        String(
            localized: "Delete (key caption)",
            defaultValue: "Delete",
            comment: "Caption under the Library panel's key that deletes the selected profile, at most six characters."
        )
    }

    var keys: [MomentaryKey] {
        [
            MomentaryKey(id: "new", caption: String(localized: "New"), name: Text("New profile")) {
                editor.addProfile()
            },
            MomentaryKey(id: "delete", caption: Self.deleteCaption, name: Text("Delete profile"), isEnabled: editor.canDeleteProfile) {
                editor.deleteProfile()
            },
            MomentaryKey(id: "import", caption: String(localized: "Import"), name: Text("Import profile")) {
                editor.importProfile()
            },
            MomentaryKey(id: "export", caption: String(localized: "Export"), name: Text("Export profile")) {
                editor.exportProfile()
            },
        ]
    }
}

/// The selected profile's speaker: the readout that opens the menu of every driver model, the caution that speaker
/// safety is unverified, and the key to the Driver Models window.
private struct SpeakerSection: View {
    let editor: LibraryEditor
    let drivers: [DriverRecord]
    let theme: PhosphorTheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        LibrarySection(title: "Speaker") {
            SpeakerReadout(editor: editor, drivers: drivers, theme: theme)
            SectionRow {
                PanelIndicator(
                    caption: String(localized: "Safety unverified"),
                    isLit: true,
                    color: .amber,
                    spokenText: String(localized: "Speaker safety is unverified.")
                )
            } key: {
                LabeledMomentaryKey(key: driverModelsKey)
            }
        }
    }
}

private extension SpeakerSection {
    var driverModelsKey: MomentaryKey {
        MomentaryKey(id: "driver-models", caption: Self.driverModelsCaption, name: Text("Driver models")) {
            openWindow(id: WorkbenchLayout.driverLibraryWindowID)
        }
    }

    /// The Driver Models key's caption. It has a key of its own, because German names the window in one word that is
    /// too wide for a caption beside the safety LED.
    static var driverModelsCaption: String {
        String(
            localized: "Driver models (key caption)",
            defaultValue: "Driver models",
            comment: "Caption under the Library panel's key that opens the Driver Models window, at most seven characters a word."
        )
    }
}

/// The connected SoundBox: its name, the LED that is lit while it is verified, and the key that renames it, which
/// only a verified board takes.
private struct SoundBoxSection: View {
    let model: WorkbenchModel
    let theme: PhosphorTheme
    @State private var isRenaming = false

    var body: some View {
        LibrarySection(title: "SoundBox") {
            PanelReadout(lines: [line], layout: Self.layout, theme: theme)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("SoundBox name")
                .accessibilityValue(Text(verbatim: line.text))
            SectionRow {
                PanelIndicator(
                    caption: String(localized: "Connected"),
                    isLit: capabilities != nil,
                    color: .cyan,
                    spokenText: model.boards.state.title
                )
            } key: {
                LabeledMomentaryKey(key: renameKey)
                    .popover(isPresented: $isRenaming) {
                        if let capabilities {
                            BoardRenameForm(currentName: capabilities.deviceName) { name in
                                isRenaming = false
                                Task { await model.renameBoard(name) }
                            }
                        }
                    }
            }
        }
        .onChange(of: capabilities == nil) { _, isUnverified in
            if isUnverified {
                isRenaming = false
            }
        }
    }
}

private extension SoundBoxSection {
    /// The readout's layout, one line that fills the panel's column.
    static let layout = PanelReadout.fillingLayout(width: LibraryPanelLayout.contentWidth)

    var line: DotMatrixLine {
        LibraryReadoutLines.soundBox(model.boards.state)
    }

    var renameKey: MomentaryKey {
        MomentaryKey(id: "rename", caption: String(localized: "Rename"), name: Text("Rename SoundBox"), isEnabled: capabilities != nil) {
            isRenaming = true
        }
    }

    /// The verified board's capabilities, or nil while no board is verified.
    var capabilities: DeviceCapabilities? {
        guard case let .verified(capabilities) = model.boards.state else {
            return nil
        }
        return capabilities
    }
}
