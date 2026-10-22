import CoreGraphics
import SwiftUI

/// The front panel's brushed metal: the mockup's metal gradient under faint, slightly slanted brush strokes and a fine
/// grain. Its top edge catches a highlight and its bottom edge lies in shade, as the window's edges do in the mockup.
struct BrushedMetal: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0x5A5D60), location: 0),
                        .init(color: Color(hex: 0x4A4C4F), location: 0.45),
                        .init(color: Color(hex: 0x3C3E40), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .shadow(.inner(color: .white.opacity(0.08), radius: 0, y: 1))
                .shadow(.inner(color: .black.opacity(0.4), radius: 2, y: -2))
            )
            .overlay {
                BrushStrokes()
            }
            .overlay {
                MetalGrain()
            }
    }
}

/// Strokes one point wide every three points, slanted ten degrees from the vertical, as the mockup's repeating
/// gradient at 100 degrees draws them.
private struct BrushStrokes: View {
    var body: some View {
        Canvas { context, size in
            let reach = (size.width * size.width + size.height * size.height).squareRoot()
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: .degrees(10))
            var strokes = Path()
            var offset = -reach / 2
            while offset < reach / 2 {
                strokes.addRect(CGRect(x: offset, y: -reach / 2, width: 1, height: reach))
                offset += 3
            }
            context.fill(strokes, with: .color(.white.opacity(0.025)))
        }
        .allowsHitTesting(false)
    }
}

/// A fine grain of white specks, tiled from one noise tile that every launch draws the same.
private struct MetalGrain: View {
    var body: some View {
        if let tile = Self.tile {
            Image(decorative: tile, scale: 2)
                .resizable(resizingMode: .tile)
                .allowsHitTesting(false)
        }
    }
}

private extension MetalGrain {
    /// The tile's edge in pixels.
    static let tileSize = 128
    /// The strongest speck's opacity, the strength of the mockup's fractal noise.
    static let maximumOpacity = 0.05

    /// A tile of white specks with random opacities up to `maximumOpacity`, from a fixed seed.
    @MainActor static let tile: CGImage? = {
        var generator = SplitMix64(seed: 0x4E58_5353)
        var pixels = [UInt8](repeating: 0, count: tileSize * tileSize * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = UInt8((Double.random(in: 0 ... maximumOpacity, using: &generator) * 255).rounded())
            pixels[index] = alpha
            pixels[index + 1] = alpha
            pixels[index + 2] = alpha
            pixels[index + 3] = alpha
        }
        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }
        return CGImage(
            width: tileSize,
            height: tileSize,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: tileSize * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }()
}

/// A small seeded generator, so the grain is the same on every launch and in every render.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
