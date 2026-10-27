import SwiftUI
import Testing
@testable import NeXTsoundWorkbench

extension RenderingTests {
    @MainActor
    struct SharedWidthRowTests {
        /// Views with a share of two thirds take two thirds of the widest whole-share view's width, even where their
        /// content asks for more, so two of them and a view 120 points wide at 10 points' spacing are 2 × 80 + 120 + 20
        /// points wide.
        @Test func aPartialShareTakesItsPartOfTheWholeViewsWidth() throws {
            let row = SharedWidthRow(spacing: 10) {
                Color.clear.frame(width: 90, height: 10).rowWidthShare(2 / 3)
                Color.clear.frame(width: 60, height: 10).rowWidthShare(2 / 3)
                Color.clear.frame(width: 120, height: 10)
            }
            let image = try #require(ImageRenderer(content: row).cgImage)
            #expect(image.width == 300)
        }
    }
}
