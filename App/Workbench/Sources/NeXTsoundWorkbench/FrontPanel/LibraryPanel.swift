import NeXTsoundCore
import SwiftUI

/// The Library's content, which the front panel shows as a sheet: the profiles with their keys, the selected profile's
/// speaker, and the connected SoundBox's name, side by side in three columns as wide as the profile keys.
///
/// Its readouts take the display color that the front panel's keys choose. The CLOSE key at the bottom right closes
/// the sheet. It is a bank of one key, so its face and its caption line up with the profile keys'. Escape does not
/// close the sheet, because a key bound to Escape would take Escape before a rename does, and Escape during a rename
/// restores the old name. While the sheet is shown, it presents the import and export panels over itself.
public struct LibraryPanel: View {
    private let model: WorkbenchModel
    private let driverLibrary: DriverLibraryModel
    @AppStorage(PhosphorTheme.storageKey) private var theme = PhosphorTheme.blue
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        WholePointFrame {
            HStack(alignment: .top, spacing: LibraryPanelLayout.columnSpacing) {
                ProfilesSection(editor: editor, theme: theme)
                    .frame(width: LibraryPanelLayout.contentWidth)
                SpeakerSection(editor: editor, drivers: driverLibrary.drivers, theme: theme)
                    .frame(width: LibraryPanelLayout.contentWidth)
                VStack(alignment: .trailing, spacing: 0) {
                    SoundBoxSection(model: model, theme: theme)
                    MomentaryKeyBank(keys: [closeKey])
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(width: LibraryPanelLayout.contentWidth)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(LibraryPanelLayout.padding)
            .fixedSize()
        }
        .background {
            PanelMetal()
        }
        .profileFileDialogs(model: model, undoManager: undoManager)
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

    /// The key that closes the sheet.
    var closeKey: MomentaryKey {
        MomentaryKey(id: "close", caption: Self.closeCaption, name: Text(verbatim: Self.closeCaption)) {
            dismiss()
        }
    }

    static var closeCaption: String {
        String(localized: "Close", comment: "Caption under the Library sheet's key that closes the sheet.")
    }
}

/// The Library panel's measurements, from the mockup.
enum LibraryPanelLayout {
    /// The width of the four profile keys, which every readout fills.
    static let contentWidth = MomentaryKeyBank.width(keyCount: 4)
    /// The space around the columns, as wide as the front panel row's side margin.
    static let padding = EdgeInsets(top: 24, leading: 24, bottom: 20, trailing: 24)
    /// The space between two sections side by side, the front panel's space between two panels.
    static let columnSpacing: CGFloat = 24
    /// The space between a section's title and its rows, and between the rows.
    static let rowSpacing: CGFloat = 12
    /// The space between an indicator's LED and its caption.
    static let indicatorSpacing: CGFloat = 8
}

/// A section of the panel: its title over its rows, with an accessory such as an indicator at the right end of the
/// title's line.
private struct LibrarySection<Accessory: View, Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: LibraryPanelLayout.rowSpacing) {
            PanelTitle(title: title)
                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
                    accessory
                }
            content
        }
    }
}

extension LibrarySection where Accessory == EmptyView {
    /// A section without an accessory on its title's line.
    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}

/// An LED with its caption beside it, which shows a state rather than starting an action.
private struct PanelIndicator: View {
    let caption: String
    let isLit: Bool
    let color: PanelLEDColor
    /// What VoiceOver reads for the indicator, which names the state the LED shows.
    let spokenText: String
    /// The side of the caption the LED stands on.
    var ledSide = HorizontalEdge.leading

    var body: some View {
        HStack(spacing: LibraryPanelLayout.indicatorSpacing) {
            if ledSide == .leading {
                PanelLED(isLit: isLit, color: color)
            }
            ControlCaption(wrappingToWidestWord: caption, alignment: ledSide == .leading ? .leading : .trailing)
            if ledSide == .trailing {
                PanelLED(isLit: isLit, color: color)
            }
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
            IndicatorKeyRow(minimumSpacing: LibraryPanelLayout.rowSpacing) {
                PanelIndicator(
                    caption: String(localized: "Safety unverified"),
                    isLit: true,
                    color: .amber,
                    spokenText: String(localized: "Speaker safety is unverified.")
                )
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

/// The connected SoundBox: its name, the CONNECTED LED at the right end of the section's title, lit while the board
/// is verified, and the key that renames it, which only a verified board takes.
private struct SoundBoxSection: View {
    let model: WorkbenchModel
    let theme: PhosphorTheme
    @State private var isRenaming = false

    var body: some View {
        LibrarySection(title: "SoundBox") {
            PanelIndicator(
                caption: String(localized: "Connected"),
                isLit: capabilities != nil,
                color: .cyan,
                spokenText: model.boards.state.title,
                ledSide: .trailing
            )
        } content: {
            PanelReadout(lines: lines, layout: Self.layout, theme: theme)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("SoundBox name")
                .accessibilityValue(Text(verbatim: LibraryReadoutLines.soundBox(model.boards.state).text))
            LabeledMomentaryKey(key: renameKey)
                .popover(isPresented: $isRenaming) {
                    if let capabilities {
                        BoardRenameForm(currentName: capabilities.deviceName) { name in
                            isRenaming = false
                            Task { await model.renameBoard(name) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onChange(of: capabilities == nil) { _, isUnverified in
            if isUnverified {
                isRenaming = false
            }
        }
    }
}

private extension SoundBoxSection {
    /// The readout's layout, two lines that fill the panel's column, so a name wider than one line still shows.
    static let layout = PanelReadout.fillingLayout(width: LibraryPanelLayout.contentWidth, lines: LibraryReadoutLines.soundBoxLines)

    var lines: [DotMatrixLine] {
        LibraryReadoutLines.soundBox(model.boards.state, cells: Self.layout.cells)
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
