import AppKit

@MainActor
func tabStackDestination(targetWindow: Window, mouseLocation: CGPoint? = nil) -> WindowDragIntentDestination? {
    guard isWindowDragIntentKindEnabled(.tabStack(targetWindowId: targetWindow.windowId)),
          let rects = targetWindow.tabStackTargetRects,
          mouseLocation.map(rects.interactionRect.contains) ?? true
    else { return nil }
    return WindowDragIntentDestination(
        kind: .tabStack(targetWindowId: targetWindow.windowId),
        previewContainerRect: rects.containerRect,
        previewRect: rects.previewRect,
        interactionRect: rects.interactionRect,
        title: "Insert Into Tabs",
        subtitle: "Drop near the top edge to add this window",
        previewStyle: .tabInsert,
        previewGeometry: .tabStrip,
        isGroup: false,
    )
}

@MainActor
func selfTabGroupTabReentryDestination(
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    guard subject == .window,
          detachOrigin == .tabStrip,
          legacyWindowTabBehaviorIsEnabled(),
          let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .tabGroup,
          targetWindow.parent === sourceParent,
          let previewRect = sourceParent.windowTabDropZoneRect,
          let interactionRect = sourceParent.windowTabDropInteractionRect,
          interactionRect.contains(mouseLocation)
    else { return nil }
    let sourceIndex = sourceWindow.ownIndex ?? 0
    let targetIndex = tabReentryTargetIndex(
        mouseLocation: mouseLocation,
        tabStripRect: previewRect,
        tabCount: sourceParent.children.count,
        sourceIndex: sourceIndex
    )

    return WindowDragIntentDestination(
        kind: .reorderTab(windowId: sourceWindow.windowId, targetIndex: targetIndex),
        previewContainerRect: sourceParent.windowDragVisibleRect ?? previewRect,
        previewRect: previewRect,
        interactionRect: interactionRect,
        title: "Return To Tabs",
        subtitle: "Drop to cancel the detach and put this tab back in the group",
        previewStyle: .tabInsert,
        previewGeometry: .tabStrip,
        isGroup: false,
    )
}

func tabReentryTargetIndex(
    mouseLocation: CGPoint,
    tabStripRect: Rect,
    tabCount: Int,
    sourceIndex: Int? = nil,
) -> Int {
    guard tabCount > 1, tabStripRect.width > 0 else { return 0 }
    let tabWidth = windowTabStripTabWidth(stripWidth: tabStripRect.width, count: tabCount)
    let firstTabMinX = tabStripRect.minX + windowTabStripContentHorizontalPadding
    return tabReorderTargetIndex(
        pointerX: mouseLocation.x,
        firstTabMinX: firstTabMinX,
        tabWidth: tabWidth,
        tabCount: tabCount,
        sourceIndex: sourceIndex,
    )
}

func tabReentrySourceVisualOffset(
    mouseLocation: CGPoint,
    tabStripRect: Rect,
    tabCount: Int,
    sourceIndex: Int,
) -> CGFloat {
    guard tabCount > 1, tabStripRect.width > 0 else { return 0 }
    let tabWidth = windowTabStripTabWidth(stripWidth: tabStripRect.width, count: tabCount)
    let effectiveTabWidth = tabWidth + windowTabStripTabSpacing
    let sourceCenterX = tabStripRect.minX
        + windowTabStripContentHorizontalPadding
        + CGFloat(sourceIndex) * effectiveTabWidth
        + tabWidth / 2
    let minOffset = -CGFloat(sourceIndex) * effectiveTabWidth
    let maxOffset = CGFloat(max(tabCount - 1 - sourceIndex, 0)) * effectiveTabWidth
    return max(min(mouseLocation.x - sourceCenterX, maxOffset), minOffset)
}

@MainActor
func currentWindowTabDropDestination(sourceWindow: Window, mouseLocation: CGPoint) -> WindowDragIntentDestination? {
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    return mouseLocation.findWindowTabDropDestination(in: targetWorkspace.rootTilingContainer, excluding: sourceWindow)
}
