import AppKit
import SwiftUI

/// The Library's list of profiles: seven lines of a readout, with the selected profile's line marked and bright.
///
/// A click selects a profile and a double click renames it, as Return does, and the arrow keys move the selection. A
/// click also gives the list the keyboard's focus without showing a ring.
/// While a profile is renamed, an invisible text field takes the typing, and the line shows what the field holds,
/// with a cursor at the caret that blinks unless motion is reduced. Return or a click elsewhere keeps the new name,
/// and Escape keeps the old one. A selection that changes from elsewhere during a rename ends it with the old name.
/// VoiceOver reads the list as a list of the profiles.
struct ProfileList: View {
    let editor: LibraryEditor
    @State private var firstVisible = 0
    @State private var rename: ProfileRename?
    @State private var cursorIsVisible = true
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PanelReadout(lines: lines, layout: Self.layout)
            .background(alignment: .topLeading) {
                ProfileRenameField(text: rename?.text) { typed in
                    rename = typed
                } onEnd: { ending in
                    endRename(ending)
                }
                .frame(width: 0, height: 0)
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                selectLine(at: tap.location)
            })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                startRename()
            })
            .panelFocus($isFocused)
            .onKeyPress(keys: Self.keys) { press in
                handle(press.key)
            }
            .onChange(of: shownFirst, initial: true) { _, first in
                firstVisible = first
            }
            .onChange(of: editor.selectedID) {
                rename = nil
            }
            .task(id: rename) {
                await blinkCursor()
            }
            .accessibilityRepresentation {
                ProfileListAccessibility(editor: editor)
            }
    }
}

/// A rename in progress: the name as typed so far, and the caret's position in it in characters.
struct ProfileRename: Equatable {
    var text: String
    var caret: Int
}

/// How a rename ends: with the typed name, and whether the list takes the keyboard's focus back, or with the old name.
enum ProfileRenameEnding {
    case committed(name: String, returnsFocus: Bool)
    case cancelled
}

private extension ProfileList {
    /// The list's layout, seven lines that fill the Library panel's column.
    static let layout = PanelReadout.fillingLayout(width: LibraryPanelLayout.contentWidth, lines: ProfileListLines.visibleLines)
    /// The distance from the readout's top to its first row of dots.
    static let dotsTop = FrontPanelLayout.frameWidth + layout.margin
    static let keys: Set<KeyEquivalent> = [.upArrow, .downArrow, .return]
    static let cursorBlinkInterval = Duration.milliseconds(530)

    /// The first profile in view, which keeps the selected one in view.
    var shownFirst: Int {
        ProfileListLines.firstVisible(previous: firstVisible, selected: editor.selectedIndex, count: editor.profiles.count)
    }

    var lines: [DotMatrixLine] {
        let renameLine = rename.map { rename in
            ProfileListLines.renameLine(text: rename.text, caret: rename.caret, cells: Self.layout.cells, showsCursor: cursorIsVisible)
        }
        return ProfileListLines.lines(
            names: editor.profiles.map(\.displayName),
            selected: editor.selectedIndex,
            firstVisible: shownFirst,
            renameLine: renameLine
        )
    }

    func selectLine(at location: CGPoint) {
        isFocused = true
        guard let line = ProfileListLines.lineIndex(at: location.y - Self.dotsTop) else {
            return
        }
        editor.select(at: shownFirst + line)
    }

    func handle(_ key: KeyEquivalent) -> KeyPress.Result {
        switch key {
        case .upArrow: editor.moveSelection(by: -1)
        case .downArrow: editor.moveSelection(by: 1)
        default: startRename()
        }
        return .handled
    }

    func startRename() {
        guard rename == nil else {
            return
        }
        let name = editor.selectedProfile.name
        rename = ProfileRename(text: name, caret: name.count)
    }

    func endRename(_ ending: ProfileRenameEnding) {
        rename = nil
        switch ending {
        case let .committed(name, returnsFocus):
            editor.rename(to: name)
            if returnsFocus {
                isFocused = true
            }
        case .cancelled:
            isFocused = true
        }
    }

    /// Shows the cursor and blinks it while a rename runs. Every change of the name or the caret restarts the blink,
    /// so the cursor never hides while it moves.
    func blinkCursor() async {
        cursorIsVisible = true
        guard
            rename != nil,
            !reduceMotion
        else {
            return
        }
        while true {
            do {
                try await Task.sleep(for: Self.cursorBlinkInterval)
            } catch {
                return
            }
            cursorIsVisible.toggle()
        }
    }
}

/// The list VoiceOver reads in place of the dots: the profiles by name, with the selected one selected.
private struct ProfileListAccessibility: View {
    let editor: LibraryEditor

    var body: some View {
        List(selection: selection) {
            ForEach(editor.profiles) { profile in
                Text(verbatim: profile.displayName)
                    .tag(profile.id)
            }
        }
        .accessibilityLabel("Profiles")
    }
}

private extension ProfileListAccessibility {
    var selection: Binding<UUID?> {
        Binding {
            editor.selectedID
        } set: { identifier in
            if let identifier {
                editor.select(identifier)
            }
        }
    }
}

/// The invisible text field a profile is renamed in.
///
/// The list draws what the field holds, so the field shows nothing and takes no room, because an image render draws a
/// placeholder over the area of every AppKit view. It is an AppKit field because its delegate sees Return and Escape
/// as commands before they reach the panel, so Escape ends the rename and leaves the panel open. It stays hidden
/// between renames, which keeps it out of the keyboard's way and out of VoiceOver's.
private struct ProfileRenameField: NSViewRepresentable {
    /// The name as typed while a rename runs, which a starting rename fills the field with, or nil without a rename.
    let text: String?
    let onEdit: (ProfileRename) -> Void
    let onEnd: (ProfileRenameEnding) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: "")
        field.isHidden = true
        field.alphaValue = 0
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.setAccessibilityLabel(String(localized: "Profile name"))
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.representable = self
        if let text, !coordinator.isEditing {
            coordinator.begin(with: text, in: field)
        } else if text == nil, coordinator.isEditing {
            coordinator.stop(field)
        }
    }

    func makeCoordinator() -> ProfileRenameCoordinator {
        ProfileRenameCoordinator(representable: self)
    }
}

/// Reports the rename field's name, caret and ending to the list.
@MainActor
private final class ProfileRenameCoordinator: NSObject, NSTextFieldDelegate {
    var representable: ProfileRenameField
    private(set) var isEditing = false
    private var selectionObserver: (any NSObjectProtocol)?

    init(representable: ProfileRenameField) {
        self.representable = representable
    }

    /// Fills the field with `text` and starts editing it with the caret after its last character, once the update
    /// that asked for it has finished.
    func begin(with text: String, in textField: NSTextField) {
        isEditing = true
        textField.stringValue = text
        textField.isHidden = false
        Task { [weak self, weak textField] in
            guard
                let self,
                let textField,
                isEditing,
                textField.window?.makeFirstResponder(textField) == true,
                let editor = textField.currentEditor() as? NSTextView
            else {
                return
            }
            editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            observeSelection(of: editor)
            report(editor)
        }
    }

    /// Ends editing without reporting an ending, because the list has ended the rename itself.
    func stop(_ textField: NSTextField) {
        finish(textField)
        textField.window?.makeFirstResponder(nil)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let editor = (notification.object as? NSTextField)?.currentEditor() as? NSTextView else {
            return
        }
        report(editor)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let textField = control as? NSTextField else {
            return false
        }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            end(.committed(name: textView.string, returnsFocus: true), in: textField)
        case #selector(NSResponder.cancelOperation(_:)):
            end(.cancelled, in: textField)
        default:
            return false
        }
        return true
    }

    /// A rename that loses the keyboard's focus to a click or to Tab keeps the new name.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard
            isEditing,
            let textField = notification.object as? NSTextField
        else {
            return
        }
        finish(textField)
        representable.onEnd(.committed(name: textField.stringValue, returnsFocus: false))
    }
}

private extension ProfileRenameCoordinator {
    func end(_ ending: ProfileRenameEnding, in textField: NSTextField) {
        finish(textField)
        textField.window?.makeFirstResponder(nil)
        representable.onEnd(ending)
    }

    func finish(_ textField: NSTextField) {
        isEditing = false
        textField.isHidden = true
        if let selectionObserver {
            NotificationCenter.default.removeObserver(selectionObserver)
        }
        selectionObserver = nil
    }

    /// Reports every move of the caret, which the arrow keys make without changing the name.
    func observeSelection(of editor: NSTextView) {
        selectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: editor,
            queue: .main
        ) { [weak self, weak editor] _ in
            MainActor.assumeIsolated {
                if let editor {
                    self?.report(editor)
                }
            }
        }
    }

    /// Reports the name and the caret, which the field editor counts in UTF-16 units and the list in characters.
    func report(_ editor: NSTextView) {
        let text = editor.string as NSString
        let caretOffset = min(editor.selectedRange().location, text.length)
        representable.onEdit(ProfileRename(text: editor.string, caret: text.substring(to: caretOffset).count))
    }
}
