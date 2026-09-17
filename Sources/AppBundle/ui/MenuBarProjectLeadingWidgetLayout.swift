import SwiftUI

/// Keeps Period and Projects together on the leading side while the remaining
/// status widgets stay on the trailing side.
struct MenuBarProjectLeadingWidgetLayout: SwiftUI.Layout {
    let separation: CGFloat
    let projectSeparation: CGFloat
    let projectCount: Int
    let cameraSafeEdges: ClosedRange<CGFloat>?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(
            width: proposal.width ?? sizes.reduce(0) { $0 + $1.width }
                + CGFloat(max(subviews.count - 1, 0)) * separation,
            height: proposal.height ?? sizes.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placements = menuBarProjectLeadingWidgetPlacements(
            subviews.map { $0.sizeThatFits(.unspecified).width },
            availableWidth: bounds.width,
            separation: separation,
            projectSeparation: projectSeparation,
            projectCount: projectCount,
            cameraSafeEdges: cameraSafeEdges
        )
        for (subview, placement) in zip(subviews, placements) {
            subview.place(
                at: CGPoint(x: bounds.minX + placement.x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: placement.width, height: bounds.height)
            )
        }
    }
}

func menuBarProjectLeadingWidgetPlacements(
    _ idealWidths: [CGFloat],
    availableWidth: CGFloat,
    separation: CGFloat,
    projectSeparation: CGFloat = standardGap,
    projectCount: Int = 1,
    cameraSafeEdges: ClosedRange<CGFloat>? = nil
) -> [MenuBarWidgetPlacement] {
    guard !idealWidths.isEmpty else { return [] }
    let widths = idealWidths.map { $0.isFinite ? max(0, $0) : 0 }
    let available = max(0, availableWidth)
    let outerGap = max(0, separation)
    let projectGap = max(0, projectSeparation)
    let lastProjectIndex = min(max(projectCount, 0), max(widths.count - 1, 0))
    let statusWidths = Array(widths.dropFirst(lastProjectIndex + 1))
    let statusTotal = statusWidths.reduce(0, +) + CGFloat(max(0, statusWidths.count - 1)) * outerGap
    let statusStart = max(0, available - statusTotal)
    var x: CGFloat = 0
    var result: [MenuBarWidgetPlacement] = []
    for (index, width) in widths.enumerated() {
        if index == lastProjectIndex + 1 {
            x = statusStart
        }
        if index > 0 {
            if index != lastProjectIndex + 1 {
                x += index > 1 && index <= lastProjectIndex ? projectGap : outerGap
            }
        }
        if let cameraSafeEdges,
           x < cameraSafeEdges.upperBound,
           x + width > cameraSafeEdges.lowerBound {
            x = cameraSafeEdges.upperBound
        }
        let end = index <= lastProjectIndex && !statusWidths.isEmpty ? statusStart - outerGap : available
        let visibleWidth = min(width, max(0, end - x))
        result.append(MenuBarWidgetPlacement(x: x, width: visibleWidth))
        x += visibleWidth
    }
    return result
}
