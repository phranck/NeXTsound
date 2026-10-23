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

/// Lays its views out side by side, each at its share of one width, as the mockup's modules share one column width.
///
/// A view's share is 1 unless `rowWidthShare(_:)` sets it, and the width is the widest view's among those with a whole
/// share. Each view gets the row's full height.
struct SharedWidthRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let widths = widths(of: subviews)
        let height = zip(subviews, widths).map { subview, width in
            subview.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height
        }
        .max() ?? 0
        return CGSize(width: widths.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0)), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var leading = bounds.minX
        for (subview, width) in zip(subviews, widths(of: subviews)) {
            subview.place(
                at: CGPoint(x: leading, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            leading += width + spacing
        }
    }
}

private extension SharedWidthRow {
    /// Each view's width: its share of the widest width among the views with a whole share. A view with a smaller
    /// share takes exactly that part, even where its content asks for more.
    func widths(of subviews: Subviews) -> [CGFloat] {
        let shares = subviews.map { $0[RowWidthShare.self] }
        let width = zip(subviews, shares).filter { $0.1 == 1 }.map { subview, _ in
            subview.sizeThatFits(.unspecified).width
        }
        .max() ?? 0
        return shares.map { width * $0 }
    }
}

/// A view's share of the width a `SharedWidthRow` gives its views.
private struct RowWidthShare: LayoutValueKey {
    static let defaultValue: CGFloat = 1
}

extension View {
    /// Sets the view's share of the width a `SharedWidthRow` gives its views, which is 1 otherwise.
    func rowWidthShare(_ share: CGFloat) -> some View {
        layoutValue(key: RowWidthShare.self, value: share)
    }
}

/// Lays out an indicator at the leading edge and a key at the trailing edge, with the capitals of the indicator's
/// caption starting level with the top of the key.
///
/// The row is as tall as the key, so the key stands where it would alone and lines up with the keys beside it. The
/// space a caption keeps over its capitals reaches above the row. The row takes two views, the indicator first.
struct IndicatorKeyRow: Layout {
    /// The space between the indicator and the key when the row is no wider than they need.
    var minimumSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard subviews.count == 2 else {
            return .zero
        }
        let indicator = subviews[0].sizeThatFits(.unspecified)
        let key = subviews[1].sizeThatFits(.unspecified)
        let width = indicator.width + minimumSpacing + key.width
        let height = max(key.height, indicator.height - Self.capitalsTop(of: subviews[0]))
        return CGSize(width: max(proposal.width ?? width, width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard subviews.count == 2 else {
            return
        }
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY - Self.capitalsTop(of: subviews[0])),
            anchor: .topLeading,
            proposal: .unspecified
        )
        subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.minY), anchor: .topTrailing, proposal: .unspecified)
    }
}

private extension IndicatorKeyRow {
    /// The distance from the indicator's top down to the top of its caption's capitals: its first text baseline less
    /// the height of the caption face's capitals.
    static func capitalsTop(of indicator: LayoutSubview) -> CGFloat {
        indicator.dimensions(in: .unspecified)[.firstTextBaseline] - FrontPanelType.capHeight
    }
}
