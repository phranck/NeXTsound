import SwiftUI
import Testing

extension RenderingTests {
    /// Two renders that ran at the same time handed back each other's pixels, so a clear view came back white.
    struct RenderedPixelsTests {
        @Test func aClearViewRendersNothingWhileAnotherViewRendersWhite() async throws {
            let clear = try await MainActor.run {
                try RenderedPixels(Color.clear.frame(width: 10, height: 10))
            }
            #expect(clear.pixel(column: 5, row: 5) == RenderedPixel(red: 0, green: 0, blue: 0))
        }

        @Test func aWhiteViewRendersWhite() async throws {
            let white = try await MainActor.run {
                try RenderedPixels(Color.white.frame(width: 10, height: 10))
            }
            #expect(white.pixel(column: 5, row: 5) == RenderedPixel(red: 255, green: 255, blue: 255))
        }
    }
}
