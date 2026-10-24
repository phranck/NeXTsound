import SwiftUI

/// The colors the front panel's controls share.
///
/// A shade that only one control uses stays with that control.
enum FrontPanelPalette {
    /// A panel's title.
    static let title = Color(hex: 0xCFCBBD)
    /// A control's caption.
    static let captionShade: UInt32 = 0x9B968A
    static let caption = Color(hex: captionShade)
    /// A lit LED and a lit legend.
    static let cyan = Color(hex: 0x00FFD8)
    /// The dark ring around a track and a cap.
    static let outline = Color.black.opacity(0.6)
    /// The lines engraved into a control's surface.
    static let engraving = Color(hex: 0x474747)
    /// The top of a display frame's shade.
    static let frameTop: UInt32 = 0x16181A
    /// The bottom of a display frame's shade.
    static let frameBottom: UInt32 = 0x0C0D0E
    /// The red of the header's LAYERED stripes, which the FLASH button takes as well.
    static let stripeRed: UInt32 = 0xC64616
    /// The yellow of the header's LAYERED stripes, which the push keys take as well.
    static let stripeYellow: UInt32 = 0xFBAC3E
}
