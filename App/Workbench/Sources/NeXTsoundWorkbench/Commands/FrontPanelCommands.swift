import SwiftUI

/// A band of the profile the front panel edits, which the band commands act on.
struct FrontPanelBand {
    let editor: FrontPanelEditor
    let index: Int
}

/// The two band settings the panel has no control for, as a band key's context menu and the Edit menu offer them.
///
/// Without a band, the commands show disabled, as the Edit menu's do while no front panel is in front.
struct BandCommandsMenu: View {
    let band: FrontPanelBand?

    var body: some View {
        Toggle("Band Enabled", isOn: isEnabled)
            .disabled(band == nil)
        Button("Reset Band") {
            if let band {
                band.editor.resetBand(band.index)
            }
        }
        .disabled(band == nil)
    }
}

private extension BandCommandsMenu {
    var isEnabled: Binding<Bool> {
        guard let band else {
            return .constant(false)
        }
        return band.editor.binding(band: band.index, \.isEnabled)
    }
}

/// The Edit menu's band commands, for the band selected on the front panel in front.
public struct FrontPanelCommands: Commands {
    @FocusedValue(\.frontPanelBand) private var band

    public var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            BandCommandsMenu(band: band)
        }
    }

    public init() {}
}

/// The View menu's commands for the display of the front panel in front: one shows the live spectrum in place of the
/// EQ curve or the curve again, as the SPECTRUM key does, and one slides the status column in or out, as the INFO key
/// does. Each title says what its command does next, so it reads Hide Info while the column stands in the display.
public struct DisplayCommands: Commands {
    @FocusedBinding(\.spectrumShown) private var isSpectrumShown
    @FocusedBinding(\.statusColumnShown) private var isStatusShown

    public var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button(isSpectrumShown == true ? Self.hideSpectrumTitle : Self.showSpectrumTitle) {
                isSpectrumShown?.toggle()
            }
            .disabled(isSpectrumShown == nil)
            Button(isStatusShown == true ? Self.hideInfoTitle : Self.showInfoTitle) {
                isStatusShown?.toggle()
            }
            .disabled(isStatusShown == nil)
        }
    }

    public init() {}
}

private extension DisplayCommands {
    static var showSpectrumTitle: String {
        String(localized: "Show Spectrum", comment: "View menu item that shows the live spectrum in place of the front panel's EQ curve.")
    }

    static var hideSpectrumTitle: String {
        String(localized: "Hide Spectrum", comment: "View menu item that shows the front panel's EQ curve in place of the live spectrum.")
    }

    static var showInfoTitle: String {
        String(localized: "Show Info", comment: "View menu item that slides the status column into the front panel's display.")
    }

    static var hideInfoTitle: String {
        String(localized: "Hide Info", comment: "View menu item that slides the status column out of the front panel's display.")
    }
}

extension FocusedValues {
    /// The band selected on the front panel whose window is in front.
    @Entry var frontPanelBand: FrontPanelBand?
    /// Whether the front panel window in front shows the live spectrum in place of its EQ curve, which the View menu's
    /// command switches.
    @Entry var spectrumShown: Binding<Bool>?
    /// Whether the front panel window in front shows its display's status column, which the View menu's command
    /// switches.
    @Entry var statusColumnShown: Binding<Bool>?
}
