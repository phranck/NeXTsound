import AppKit
import SwiftUI

/// The type of the panel's titles and captions: JetBrains Mono at 11 pt.
enum FrontPanelType {
    static let size: CGFloat = 11
    /// One line, the face's ascender and descender at that size.
    static let lineHeight: CGFloat = 14.5
    /// The line height SwiftUI sets the face in, which `NSLayoutManager.defaultLineHeight(for:)` reports as well.
    static let textLineHeight: CGFloat = 14
    /// A title's letter spacing of 0.14 em.
    static let titleTracking = size * 0.14
    /// A caption's letter spacing of 0.06 em.
    static let captionTracking = size * 0.06

    static var font: Font {
        .custom(FrontPanelFonts.captions, size: size)
    }

    /// The face as AppKit sets it, for the measures SwiftUI's font does not give. It is looked up each time, because
    /// the face is only found once the front panel has registered it.
    static var appKitFont: NSFont? {
        NSFont(name: FrontPanelFonts.captions, size: size)
    }
}
