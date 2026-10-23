import CoreGraphics
import SwiftUI
import Testing

/// The pixels of a view rendered at scale 2, as 8-bit sRGB with the top row first. A transparent pixel reads as
/// black.
///
/// Only the rendering needs the main actor. The pixels can be read anywhere, so a scan of millions of them leaves
/// the main actor to the tests running beside it.
struct RenderedPixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    @MainActor init(_ content: some View) throws {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        width = image.width
        height = image.height
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
        self.bytes = bytes
    }
}

extension RenderedPixels {
    func pixel(column: Int, row: Int) -> RenderedPixel {
        let offset = (row * width + column) * 4
        return RenderedPixel(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
    }
}

/// One rendered pixel's color in 8-bit sRGB.
struct RenderedPixel: Equatable {
    let red: Int
    let green: Int
    let blue: Int
}
