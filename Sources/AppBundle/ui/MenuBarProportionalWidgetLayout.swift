import SwiftUI

/// Keep widgets at their content-driven widths and trail the group within the bar.
/// When the bar is too narrow, shrink every widget proportionally.
struct MenuBarProportionalWidgetLayout: SwiftUI.Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(
            width: proposal.width ?? sizes.reduce(0) { $0 + $1.width },
            height: proposal.height ?? sizes.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let idealWidths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let widths = menuBarProportionalWidgetWidths(idealWidths, availableWidth: bounds.width)
        var x = bounds.maxX - widths.reduce(0, +)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: widths[index], height: bounds.height)
            )
            x += widths[index]
        }
    }
}

func menuBarProportionalWidgetWidths(_ idealWidths: [CGFloat], availableWidth: CGFloat) -> [CGFloat] {
    guard !idealWidths.isEmpty else { return [] }
    let weights = idealWidths.map { $0.isFinite ? max(0, $0) : 0 }
    let total = weights.reduce(0, +)
    let available = max(0, availableWidth)
    guard total > available else { return weights }
    var remaining = available
    return weights.enumerated().map { index, weight in
        let width = index == weights.count - 1
            ? remaining
            : min(remaining, total > 0 ? available * weight / total : available / CGFloat(weights.count))
        remaining -= width
        return width
    }
}
