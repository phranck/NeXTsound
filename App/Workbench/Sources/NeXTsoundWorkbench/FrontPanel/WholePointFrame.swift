import SwiftUI

/// Rounds its content's size up to whole points and keeps the content at the top leading corner.
///
/// The dot grids give the front panel and the Library panel half-point heights, and a window's hosting view measures
/// its content in whole points. The host would center a panel and leave a strip above it unpainted, so the rounding
/// moves the remainder inside the metal at the bottom.
struct WholePointFrame: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
    }
}
