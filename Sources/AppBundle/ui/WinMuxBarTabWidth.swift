import CoreGraphics

/// Keep sparse tabs compact while sharing constrained space evenly.
func winMuxBarTabWidth(
    availableWidth: CGFloat,
    count: Int,
    spacing: CGFloat,
    maximumWidth: CGFloat
) -> CGFloat {
    guard count > 0 else { return 0 }
    let contentWidth = max(0, availableWidth - max(0, spacing) * CGFloat(count - 1))
    return min(max(0, maximumWidth), contentWidth / CGFloat(count))
}
