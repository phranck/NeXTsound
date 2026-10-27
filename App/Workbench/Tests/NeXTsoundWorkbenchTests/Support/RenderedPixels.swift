import CoreGraphics
import SwiftUI
import Testing

/// The pixels of a view rendered at scale 2, as 8-bit sRGB with the top row first. A transparent pixel reads as
/// black.
///
/// Only the rendering needs the main actor. The pixels can be read anywhere, so a scan of millions of them leaves
/// the main actor to the tests running beside it.
///
/// On the CI host, `ImageRenderer` now and then returns an image with no pixel drawn for the same view that renders
/// in full on the next run, which no change to the view explains. An image without a visible pixel is therefore
/// rendered once more. A view that really draws nothing comes back empty a second time and keeps its empty pixels, so
/// a test that expects something drawn still fails.
struct RenderedPixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    @MainActor init(_ content: some View) throws {
        var render = try Self.render(content)
        if !render.hasVisiblePixel {
            // The line shows in the CI log how often the host returns an empty image.
            print("RenderedPixels: ImageRenderer returned an image without a visible pixel; rendering once more.")
            render = try Self.render(content)
        }
        width = render.width
        height = render.height
        bytes = render.bytes
    }
}

extension RenderedPixels {
    func pixel(column: Int, row: Int) -> RenderedPixel {
        let offset = (row * width + column) * 4
        return RenderedPixel(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
    }
}

private extension RenderedPixels {
    /// One render's size and premultiplied RGBA bytes.
    struct Render {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        /// Whether any pixel has an alpha above zero.
        var hasVisiblePixel: Bool {
            stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 }
        }
    }

    @MainActor static func render(_ content: some View) throws -> Render {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return context != nil
        }
        try #require(drawn)
        return Render(width: image.width, height: image.height, bytes: bytes)
    }
}

/// One rendered pixel's color in 8-bit sRGB.
struct RenderedPixel: Equatable {
    let red: Int
    let green: Int
    let blue: Int
}
