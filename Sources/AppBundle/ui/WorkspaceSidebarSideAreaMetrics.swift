import AppKit

// Swift identifiers cannot contain hyphens; this is the `standard-gap` token.
let workspaceSidebarStandardGap = WinMuxSpacing.compact
let workspaceSidebarCompactGridHorizontalPadding = 2 * workspaceSidebarStandardGap
let workspaceSidebarCompactGridCellSize = workspaceSidebarCompactAppIconSize
// The panel adds one shared gap on either side of this content width.
let workspaceSidebarCompactContentWidth = workspaceSidebarCompactGridCellSize +
    2 * workspaceSidebarCompactGridHorizontalPadding - 2 * workspaceSidebarStandardGap

struct WorkspaceSidebarSideAreaMetrics: Equatable, Sendable {
    static let standard = WorkspaceSidebarSideAreaMetrics()

    let outerInset: CGFloat
    let mainContentGap: CGFloat
    let minimumWindowCanvasOuterGap: CGFloat
    let edgeTriggerWidth: CGFloat
    let plateCornerRadius: CGFloat

    init(
        outerInset: CGFloat = WinMuxSpacing.regular,
        mainContentGap: CGFloat = WinMuxSpacing.regular,
        minimumWindowCanvasOuterGap: CGFloat = workspaceSidebarStandardGap,
        edgeTriggerWidth: CGFloat = 4,
        plateCornerRadius: CGFloat = 18
    ) {
        self.outerInset = outerInset
        self.mainContentGap = mainContentGap
        self.minimumWindowCanvasOuterGap = minimumWindowCanvasOuterGap
        self.edgeTriggerWidth = edgeTriggerWidth
        self.plateCornerRadius = plateCornerRadius
    }

    func sideAreaReservation(expandedWidth: CGFloat) -> CGFloat {
        max(expandedWidth, 1) + outerInset + mainContentGap
    }

    func windowCanvasLeftInset(visibleWidth: CGFloat) -> CGFloat {
        max(visibleWidth, 1) + outerInset + mainContentGap
    }

    func visualSidebarFrame(in hostFrame: NSRect, visibleWidth: CGFloat) -> NSRect {
        let clampedWidth = min(max(visibleWidth, 1), max(hostFrame.width - (2 * outerInset), 1))
        let availableHeight = max(hostFrame.height - (2 * outerInset), 1)
        return NSRect(
            x: hostFrame.minX + outerInset,
            y: hostFrame.minY + outerInset,
            width: clampedWidth,
            height: availableHeight
        )
    }

    func sideAreaBackgroundFrame(in hostFrame: NSRect, visibleWidth: CGFloat, expandedWidth: CGFloat) -> NSRect {
        let backgroundWidth = min(
            sideAreaReservation(expandedWidth: min(max(visibleWidth, 1), max(expandedWidth, 1))),
            max(hostFrame.width, 1)
        )
        return NSRect(
            x: hostFrame.minX,
            y: hostFrame.minY,
            width: backgroundWidth,
            height: max(hostFrame.height, 1)
        )
    }

    func edgeTriggerFrame(in hostFrame: NSRect) -> NSRect {
        NSRect(
            x: hostFrame.minX,
            y: hostFrame.minY,
            width: max(edgeTriggerWidth, 1),
            height: hostFrame.height
        )
    }
}
