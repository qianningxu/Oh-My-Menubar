import AppKit
import Common

@MainActor
func windowResizePreviewTileItems(
    container: TilingContainer,
    point: CGPoint,
    width: CGFloat,
    height: CGFloat,
    virtual: Rect,
    context: WindowResizePreviewLayoutContext,
    activeWindowId: UInt32?,
) -> [WindowResizePreviewItem] {
    guard !container.children.isEmpty else { return [] }

    var items: [WindowResizePreviewItem] = []
    var point = point
    var virtualPoint = virtual.topLeftCorner
    let orientation = container.orientation
    let availableDimension = orientation == .h ? width : height
    let weights = constrainedTileWeights(
        proposed: container.children.map { context.weight(for: $0, orientation: orientation) },
        minimums: container.minimumTileWeights(gaps: context.resolvedGaps),
        available: availableDimension
    )

    let rawGap = CGFloat(context.resolvedGaps.inner.get(orientation))
    let lastIndex = container.children.indices.last
    for (index, child) in container.children.enumerated() {
        let adjustedWeight = weights[index]
        let gap = rawGap - (index == 0 ? rawGap / 2 : 0) - (index == lastIndex ? rawGap / 2 : 0)
        let childPoint = index == 0 ? point : point.addingOffset(orientation, rawGap / 2)
        let childWidth = orientation == .h ? max(adjustedWeight - gap, 0) : max(width, 0)
        let childHeight = orientation == .v ? max(adjustedWeight - gap, 0) : max(height, 0)
        let childVirtual = Rect(
            topLeftX: virtualPoint.x,
            topLeftY: virtualPoint.y,
            width: orientation == .h ? max(adjustedWeight, 0) : max(width, 0),
            height: orientation == .v ? max(adjustedWeight, 0) : max(height, 0),
        )
        items += windowResizePreviewItems(
            node: child,
            point: childPoint,
            width: childWidth,
            height: childHeight,
            virtual: childVirtual,
            context: context,
            activeWindowId: activeWindowId,
        )
        virtualPoint = orientation == .h
            ? virtualPoint.addingXOffset(adjustedWeight)
            : virtualPoint.addingYOffset(adjustedWeight)
        point = orientation == .h
            ? point.addingXOffset(adjustedWeight)
            : point.addingYOffset(adjustedWeight)
    }
    return items
}
