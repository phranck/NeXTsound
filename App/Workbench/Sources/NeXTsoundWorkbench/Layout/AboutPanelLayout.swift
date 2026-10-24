import SwiftUI

/// The About window's measurements, in the panels' measure.
enum AboutPanelLayout {
    /// The window's width, which leaves the header's stripes room on both sides of the wordmark.
    static let width: CGFloat = 560
    /// The icon's edge.
    static let iconSize: CGFloat = 128
    /// The icon's shadow color. The shadow falls downward onto the metal, as the light falls on the panels from above.
    static let iconShadowColor = Color.black.opacity(0.55)
    /// How far the icon's shadow blurs out.
    static let iconShadowRadius: CGFloat = 6
    /// How far the icon's shadow falls below the icon.
    static let iconShadowOffset: CGFloat = 5
    /// The space around the content. The top leaves the window's buttons room above the icon, as the front panel's
    /// padding leaves them room above its header.
    static let padding = EdgeInsets(top: 30, leading: 24, bottom: 24, trailing: 24)
    /// The space between the icon, the header, the readout and the copyright.
    static let rowSpacing: CGFloat = 12
}
