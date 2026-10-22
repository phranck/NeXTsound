import CoreText
import Foundation

/// The faces the front panel is set in.
///
/// Both ship as package resources and are registered for this process before the first text asks for them, because
/// SwiftUI draws a face it cannot find by name in Helvetica.
enum FrontPanelFonts {
    /// The wordmark's face, Monoton, by the name its file's name table gives.
    static let wordmark = "Monoton-Regular"
    /// The face of the panel's titles and captions, JetBrains Mono.
    static let captions = "JetBrainsMono-Regular"
}

extension FrontPanelFonts {
    /// Registers both faces once.
    static let registration: Void = {
        for name in [wordmark, captions] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}
