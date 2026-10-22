import SwiftUI

/// Lays its views out side by side and spreads them over its width, so the outer ones line up with its edges and
/// the space between them is shared equally. A single view sits in the middle.
///
/// Each view gets the row's full height, so a column in it can push its lower control to the panel's caption line.
struct SpreadRow: Layout {
    /// The space between two views when the row is no wider than they need.
    var minimumSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = sizes.map(\.width).reduce(0, +) + minimumSpacing * CGFloat(max(subviews.count - 1, 0))
        let height = sizes.map(\.height).max() ?? 0
        return CGSize(width: max(proposal.width ?? width, width), height: max(proposal.height ?? height, height))
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard subviews.count > 1 else {
            subviews.first?.place(
                at: CGPoint(x: bounds.midX, y: bounds.minY),
                anchor: .top,
                proposal: ProposedViewSize(width: widths.first, height: bounds.height)
            )
            return
        }
        let spacing = max((bounds.width - widths.reduce(0, +)) / CGFloat(subviews.count - 1), minimumSpacing)
        var leading = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(
                at: CGPoint(x: leading, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            leading += width + spacing
        }
    }
}

/// Lays its views out side by side at one width, the widest view's, as the mockup's modules share one column width.
///
/// Each view gets the row's full height.
struct EqualWidthRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = columnWidth(of: subviews)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: width * CGFloat(subviews.count) + spacing * CGFloat(max(subviews.count - 1, 0)), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let width = columnWidth(of: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
        }
    }
}

private extension EqualWidthRow {
    func columnWidth(of subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    }
}
