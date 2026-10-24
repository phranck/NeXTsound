import SwiftUI

/// The File menu's profile commands, which act on the library through the window in front.
///
/// They take the place of the menu's New Window item, because the profile is what this app makes new. Delete Profile
/// has no shortcut, so Command-Delete keeps deleting text in a text field.
public struct LibraryCommands: Commands {
    @FocusedValue(\.libraryEditor) private var editor

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Profile") { editor?.addProfile() }
                .keyboardShortcut("n")
                .disabled(editor == nil)
            Button("Delete Profile") { editor?.deleteProfile() }
                .disabled(editor?.canDeleteProfile != true)
            Divider()
            Button("Import Profile…") { editor?.importProfile() }
                .keyboardShortcut("o")
                .disabled(editor == nil)
            Button("Export Profile…") { editor?.exportProfile() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(editor == nil)
        }
    }

    public init() {}
}

/// The View menu's command that shows the Library sheet on the front panel window.
public struct LibrarySheetCommands: Commands {
    @FocusedBinding(\.libraryShown) private var isLibraryShown

    public var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button(String(localized: "Show Library", comment: "View menu item that shows the Library sheet on the front panel.")) {
                isLibraryShown = true
            }
            .disabled(isLibraryShown != false)
        }
    }

    public init() {}
}

extension FocusedValues {
    /// The library editor of the window in front, which the File menu's profile commands act through.
    @Entry var libraryEditor: LibraryEditor?
    /// Whether the front panel window in front shows the Library sheet, which the View menu's command sets.
    @Entry var libraryShown: Binding<Bool>?
}
