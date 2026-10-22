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

extension FocusedValues {
    /// The band selected on the front panel whose window is in front.
    @Entry var frontPanelBand: FrontPanelBand?
}
