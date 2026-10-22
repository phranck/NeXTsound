import CoreGraphics
import SwiftUI
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct ControlCaptionTests {
    /// A caption beside an LED or under a single key is as wide as its widest word, which SwiftUI must never find too
    /// narrow for that word, or it would break the word itself.
    @Test func aCaptionAsNarrowAsItsWidestWordBreaksOnlyBetweenWords() throws {
        _ = FrontPanelFonts.registration
        #expect(try lineCount(of: "Driver models") == 2)
        #expect(try lineCount(of: "Safety unverified") == 2)
        #expect(try lineCount(of: "Connected") == 1)
        #expect(try lineCount(of: "Treibermodelle") == 1)
    }
}

/// The lines a caption as narrow as its widest word takes, from the height it renders at, which is a line's height for
/// every line, as in the mockup.
@MainActor
private func lineCount(of caption: String) throws -> Int {
    let image = try #require(ImageRenderer(content: ControlCaption(wrappingToWidestWord: caption)).cgImage)
    return Int((CGFloat(image.height) / FrontPanelType.lineHeight).rounded())
}
