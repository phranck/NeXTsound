import AppKit
import SwiftUI

/// The Edit menu's Cut, Copy, Paste, Delete and Select All, which every text field of the app reaches through them.
///
/// A text field's ⌘X, ⌘C, ⌘V and ⌘A are the key equivalents of these menu items, so without them no field can cut,
/// copy or paste. `.commandsRemoved()` on any of the app's scenes takes them away, and both scenes need it to keep
/// their windows out of the Window menu. Each item sends the standard AppKit action to the first responder, which is the
/// field with the focus.
public struct PasteboardCommands: Commands {
    public var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button(String(localized: "Cut", comment: "Edit menu item that cuts the selected text.")) {
                Self.send(#selector(NSText.cut(_:)))
            }
            .keyboardShortcut("x")
            Button(String(localized: "Copy", comment: "Edit menu item that copies the selected text.")) {
                Self.send(#selector(NSText.copy(_:)))
            }
            .keyboardShortcut("c")
            Button(String(localized: "Paste", comment: "Edit menu item that pastes text from the clipboard.")) {
                Self.send(#selector(NSText.paste(_:)))
            }
            .keyboardShortcut("v")
            Button(String(
                localized: "Delete (Edit menu)",
                defaultValue: "Delete",
                comment: "Edit menu item that deletes the selected text."
            )) {
                Self.send(#selector(NSText.delete(_:)))
            }
            Button(String(localized: "Select All", comment: "Edit menu item that selects all text in the field.")) {
                Self.send(#selector(NSText.selectAll(_:)))
            }
            .keyboardShortcut("a")
        }
    }

    public init() {}
}

@MainActor
private extension PasteboardCommands {
    /// Sends `action` along the responder chain, starting at the first responder of the key window.
    static func send(_ action: Selector) {
        NSApplication.shared.sendAction(action, to: nil, from: nil)
    }
}
