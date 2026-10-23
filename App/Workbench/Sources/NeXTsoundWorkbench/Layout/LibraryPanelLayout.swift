import SwiftUI

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
