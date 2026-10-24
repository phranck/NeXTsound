import SwiftUI

/// The front panel's measurements, from the approved mockup.
enum FrontPanelLayout {
    static let panelPadding = EdgeInsets(top: 26, leading: 30, bottom: 22, trailing: 30)
    static let bayMargin = EdgeInsets(top: 2, leading: 36, bottom: 20, trailing: 36)
    static let screenPadding = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
    static let bayRadius: CGFloat = 10
    /// The width of the dark frame around every display.
    static let frameWidth: CGFloat = 2
    /// The space between a control and the caption under it.
    static let captionSpacing: CGFloat = 5
}
