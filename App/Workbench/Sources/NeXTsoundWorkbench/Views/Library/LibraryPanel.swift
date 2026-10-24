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
                ProfilesSection(editor: editor)
                    .frame(width: LibraryPanelLayout.contentWidth)
                SpeakerSection(editor: editor, drivers: driverLibrary.drivers)
                    .frame(width: LibraryPanelLayout.contentWidth)
                VStack(alignment: .trailing, spacing: 0) {
                    SoundBoxSection(model: model)
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
        .environment(\.phosphorTheme, theme)
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
    /// What VoiceOver reads for the indicator, which names the state the LED shows.
    let spokenText: String
    /// The side of the caption the LED stands on.
    var ledSide = HorizontalEdge.leading

    var body: some View {
        HStack(spacing: LibraryPanelLayout.indicatorSpacing) {
            if ledSide == .leading {
                PanelLED(isLit: isLit)
            }
            ControlCaption(wrappingToWidestWord: caption, alignment: ledSide == .leading ? .leading : .trailing)
            if ledSide == .trailing {
                PanelLED(isLit: isLit)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenText))
    }
}

/// The profiles: the list over the keys that add, delete, import and export one.
private struct ProfilesSection: View {
    let editor: LibraryEditor

    var body: some View {
        LibrarySection(title: "Profiles") {
            ProfileList(editor: editor)
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

/// The selected profile's speaker: the readout that opens the menu of every driver model, and the key to the Driver
/// Models window.
private struct SpeakerSection: View {
    let editor: LibraryEditor
    let drivers: [DriverRecord]
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        LibrarySection(title: "Speaker") {
            SpeakerReadout(editor: editor, drivers: drivers)
            LabeledMomentaryKey(key: driverModelsKey)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private extension SpeakerSection {
    var driverModelsKey: MomentaryKey {
        MomentaryKey(id: "driver-models", caption: Self.driverModelsCaption, name: Text("Driver models")) {
            openWindow(id: WorkbenchWindows.driverLibraryWindowID)
        }
    }

    /// The Driver Models key's caption. It has a key of its own, because German names the window in one word,
    /// Treibermodelle, which is too wide for the caption under a single key.
    static var driverModelsCaption: String {
        String(
            localized: "Driver models (key caption)",
            defaultValue: "Driver models",
            comment: "Caption under the Library panel's key that opens the Driver Models window, at most seven characters a word."
        )
    }
}

/// The connected SoundBox: its name, the CONNECTED LED at the right end of the section's title, lit while the board
/// is verified, and the key that opens the board's form, which only a verified board takes. A board whose metadata
/// the monitor read gets EDIT and the form for its name and owner metadata; any other gets RENAME and the name alone.
private struct SoundBoxSection: View {
    let model: WorkbenchModel
    @State private var isEditing = false

    var body: some View {
        LibrarySection(title: "SoundBox") {
            PanelIndicator(
                caption: String(localized: "Connected"),
                isLit: capabilities != nil,
                spokenText: model.boards.state.title,
                ledSide: .trailing
            )
        } content: {
            PanelReadout(lines: lines, layout: Self.layout)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("SoundBox name")
                .accessibilityValue(Text(verbatim: LibraryReadoutLines.soundBox(model.boards.state).text))
            LabeledMomentaryKey(key: formKey)
                .popover(isPresented: $isEditing) {
                    if let capabilities {
                        SoundBoxForm(model: model, capabilities: capabilities) {
                            isEditing = false
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onChange(of: capabilities == nil) { _, isUnverified in
            if isUnverified {
                isEditing = false
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

    var formKey: MomentaryKey {
        if model.boards.metadata != nil {
            return MomentaryKey(id: "edit", caption: Self.editCaption, name: Text("Edit SoundBox"), isEnabled: capabilities != nil) {
                isEditing = true
            }
        }
        return MomentaryKey(
            id: "rename",
            caption: String(localized: "Rename"),
            name: Text("Rename SoundBox"),
            isEnabled: capabilities != nil
        ) {
            isEditing = true
        }
    }

    static var editCaption: String {
        String(
            localized: "Edit",
            comment: "Caption under the Library panel's key that edits the SoundBox and its owner details, at most six characters."
        )
    }

    var capabilities: DeviceCapabilities? {
        model.boards.state.verifiedCapabilities
    }
}

/// The popover's form for a verified board: the name and owner metadata for a board whose metadata the monitor read,
/// and the name alone otherwise. A board without read metadata never gets the metadata form, because writing it would
/// clear what the board carries.
private struct SoundBoxForm: View {
    let model: WorkbenchModel
    let capabilities: DeviceCapabilities
    let onClose: () -> Void

    var body: some View {
        if let metadata = model.boards.metadata {
            BoardEditForm(
                capabilities: capabilities,
                metadata: metadata,
                register: model.serialNumbersAreAvailable ? model.serialNumbers : nil
            ) { name, metadata in
                onClose()
                Task { await model.editBoard(name: name, metadata: metadata) }
            }
        } else {
            BoardRenameForm(currentName: capabilities.deviceName) { name in
                onClose()
                Task { await model.renameBoard(name) }
            }
        }
    }
}
