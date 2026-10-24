import SwiftUI

/// A CSS `inset` box shadow on a shape: the shade its outside casts inward, offset and blurred, at full strength
/// whatever the shape is filled with.
///
/// SwiftUI's inner shadow style takes its strength from the fill it shades, so on a translucent fill it fades with the
/// fill, while this shadow keeps its own opacity. The blur is given as CSS gives it, twice the Gaussian's deviation.
struct InsetShadow<ShadowShape: Shape>: View {
    let shape: ShadowShape
    let color: Color
    var blur: CGFloat = 0
    var offset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let reach = blur * 2 + max(abs(offset.width), abs(offset.height)) + 1
            Path { outside in
                outside.addRect(bounds.insetBy(dx: -reach, dy: -reach))
                outside.addPath(shape.path(in: bounds))
            }
            .fill(color, style: FillStyle(eoFill: true))
            .offset(offset)
            .blur(radius: blur / 2)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}
