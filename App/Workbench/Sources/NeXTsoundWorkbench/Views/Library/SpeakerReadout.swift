import AppKit
import NeXTsoundCore
import SwiftUI

/// The selected profile's speaker in a readout of two lines, which opens the native menu of every driver model over
/// itself, the way a pop-up button's menu opens over the button.
///
/// A click opens the menu, and so do Space, Return and the down arrow while the readout has the keyboard's focus,
/// which shows no ring. VoiceOver reads it as a pop-up button with the speaker as its value.
struct SpeakerReadout: View {
    let editor: LibraryEditor
    let drivers: [DriverRecord]
    @State private var menu = SpeakerMenu()
    @FocusState private var isFocused: Bool

    var body: some View {
        PanelReadout(lines: lines, layout: Self.layout)
            .background(alignment: .topLeading) {
                SpeakerMenuAnchor(menu: menu)
                    .frame(width: 0, height: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isFocused = true
                openMenu()
            }
            .panelFocus($isFocused)
            .onKeyPress(keys: Self.menuKeys) { _ in
                openMenu()
                return .handled
            }
            .accessibilityRepresentation {
                Picker("Speaker", selection: selection) {
                    Text("Not selected").tag(UUID?.none)
                    ForEach(drivers) { driver in
                        Text(verbatim: driver.name).tag(Optional(driver.id))
                    }
                }
                .pickerStyle(.menu)
            }
    }
}

extension SpeakerReadout {
    /// The readout's layout, two lines that fill the Library panel's column.
    static let layout = PanelReadout.fillingLayout(width: LibraryPanelLayout.contentWidth, lines: LibraryReadoutLines.speakerLines)
}

private extension SpeakerReadout {
    /// The keys that open the menu, as they open a pop-up button's.
    static let menuKeys: Set<KeyEquivalent> = [.space, .return, .downArrow]

    var lines: [DotMatrixLine] {
        LibraryReadoutLines.speaker(editor.selectedProfile.speaker?.name, cells: Self.layout.cells)
    }

    var selection: Binding<UUID?> {
        Binding {
            editor.selectedProfile.speaker?.id
        } set: { identifier in
            editor.selectSpeaker(id: identifier, from: drivers)
        }
    }

    func openMenu() {
        menu.open(drivers: drivers, selectedID: editor.selectedProfile.speaker?.id) { identifier in
            editor.selectSpeaker(id: identifier, from: drivers)
        }
    }
}

/// Opens the native menu of every driver model at its anchor, with the current choice checked and placed over the
/// anchor, as a pop-up button places it over itself.
@MainActor
final class SpeakerMenu: NSObject {
    fileprivate weak var anchor: NSView?
    private var onSelect: ((UUID?) -> Void)?

    /// Opens the menu of `drivers` with the one whose identifier is `selectedID` checked, or Not selected without
    /// one, and reports the chosen driver's identifier to `onSelect`, or nil for Not selected.
    func open(drivers: [DriverRecord], selectedID: UUID?, onSelect: @escaping (UUID?) -> Void) {
        guard let anchor else {
            return
        }
        self.onSelect = onSelect
        let menu = NSMenu()
        menu.addItem(item(title: String(localized: "Not selected"), identifier: nil, selectedID: selectedID))
        for driver in drivers {
            menu.addItem(item(title: driver.name, identifier: driver.id, selectedID: selectedID))
        }
        menu.popUp(positioning: menu.items.first { $0.state == .on }, at: .zero, in: anchor)
    }
}

private extension SpeakerMenu {
    func item(title: String, identifier: UUID?, selectedID: UUID?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = identifier
        item.state = identifier == selectedID ? .on : .off
        return item
    }

    @objc func choose(_ item: NSMenuItem) {
        onSelect?(item.representedObject as? UUID)
    }
}

/// The point the speaker menu opens at, the readout's top leading corner.
///
/// It takes no room, because an image render draws a placeholder over the area of every AppKit view.
private struct SpeakerMenuAnchor: NSViewRepresentable {
    let menu: SpeakerMenu

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        menu.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        menu.anchor = view
    }
}
