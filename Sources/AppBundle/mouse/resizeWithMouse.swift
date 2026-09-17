import AppKit
import Common

func resizedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let notif = notif as String
    let windowId = ax.containingWindowId()
    Task { @MainActor in
        if WindowMouseInteractionOpacityController.shared.shouldSuppressObserverEvent(windowId: windowId) {
            return
        }
        if shouldIgnoreAxObserverEventForPostDragSuppression(windowId: windowId, notif: notif) {
            return
        }
        guard RunSessionGuard.isServerEnabled != nil else { return }
        if let windowId, isContinuingManagedDragSessionForResizedEvent(windowId) { return }
        guard let windowId, let window = Window.get(byId: windowId), try await isResizeManipulatedWithMouse(window) else {
            scheduleRefreshSession(.ax(notif))
            return
        }
        guard window.parent is TilingContainer else {
            scheduleRefreshSession(.ax(notif))
            return
        }
        WindowMouseInteractionDriver.shared.startResize(windowId: window.windowId)
    }
}

@MainActor
private func isResizeManipulatedWithMouse(_ window: Window) async throws -> Bool {
    let driver = WindowMouseInteractionDriver.shared
    if isLeftMouseButtonDown, !window.isHiddenInCorner,
       getCurrentMouseManipulationKind() != .move,
       driver.pendingResizeCandidate?.windowId == window.windowId || driver.resizeSession?.windowId == window.windowId {
        return true
    }
    return try await isManipulatedWithMouse(window)
}

@MainActor
func resetManipulatedWithMouseIfPossible() async throws {
    guard WindowMouseInteractionDriver.shared.flushingResizeSession == nil else { return }
    await WindowMouseInteractionDriver.shared.flushBeforeMouseUp()
    let didApplyPendingDragIntent = applyPendingWindowDragIntentIfPossible()
    clearPendingWindowDragIntent()
    if currentlyManipulatedWithMouseWindowId != nil || didApplyPendingDragIntent {
        armGlobalPostDragAxObserverSuppression()
        cancelManipulatedWithMouseState()
        scheduleRefreshSession(.resetManipulatedWithMouse, optimisticallyPreLayoutWorkspaces: true)
    }
    WindowMouseInteractionDriver.shared.stop()
}

private let adaptiveWeightBeforeResizeWithMouseKey = TreeNodeUserDataKey<CGFloat>(key: "adaptiveWeightBeforeResizeWithMouseKey")

@MainActor
func resizeWithMouse(_ window: Window) async throws { // todo cover with tests
    syncClosedWindowsCacheToCurrentWorld()
    guard let parent = window.parent else { return }
    switch parent.cases {
        case .workspace, .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return // Nothing to do for floating, or unconventional windows
        case .tilingContainer:
            guard let rect = try await window.getAxRect() else { return }
            WindowMouseInteractionDriver.shared.startResize(windowId: window.windowId)
            updateCompositedResizePreview(window, rect: rect)
    }
}

@MainActor
func updateCompositedResizePreview(_ window: Window, rect: Rect) {
    syncClosedWindowsCacheToCurrentWorld()
    let boundedRect = resizeProposal(window, rect: rect)?.rect ?? rect
    WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction(showFrameOnly: false)
    if resizePreviewHasVisibleChange(from: rect, to: boundedRect) {
        WindowMouseInteractionDriver.shared.constrainResizePointerIfNeeded(from: rect, to: boundedRect)
        WindowMouseInteractionDriver.shared.enqueueLiveResizeFrame(window: window, frame: boundedRect)
    }
    let rect = boundedRect
    guard let workspace = window.nodeWorkspace,
          workspace.isVisible,
          let weightMap = proposedResizeWeightMap(window, rect: rect)
    else {
        logWindowDragLive("resizePreview hide requested reason=resizePreview.no-workspace-or-weightMap window=\(window.windowId) workspace=\(window.nodeWorkspace?.name.description ?? "nil") visible=\(window.nodeWorkspace?.isVisible.description ?? "nil") hasWeightMap=\(proposedResizeWeightMap(window, rect: rect) != nil)")
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "resizePreview.no-workspace-or-weightMap")
        return
    }
    let items = windowResizePreviewItems(
        in: workspace, weightMap: weightMap, excludingActiveWindowId: nil)
        .filter { Window.get(byId: $0.id)?.isFloating != true }
    let canvas = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps.toAppKitScreenRect
    let visible = workspace.workspaceMonitor.visibleRect.toAppKitScreenRect
    // Cover the native window shadows and outer gutters too, using the exact
    // workspace canvas color. Keep the workspace tabs above this backing.
    let backing = CGRect(x: visible.minX, y: visible.minY, width: visible.width,
        height: min(visible.maxY, canvas.maxY + WinMuxSpacing.comfortable) - visible.minY)
    WindowResizePreviewPanel.shared.beginStableFrame(backing)
    WindowResizePreviewPanel.shared.show(items, shadeOnly: true)
}

@MainActor
func applyResizeWithMouse(_ window: Window, rect: Rect) {
    syncClosedWindowsCacheToCurrentWorld()
    guard let weightMap = proposedResizeWeightMap(window, rect: rect) else { return }
    for change in weightMap.changes {
        change.node.setWeight(change.orientation, change.weight)
    }
    currentlyManipulatedWithMouseWindowId = window.windowId
    setCurrentMouseManipulationKind(.resize)
    clearPendingWindowDragIntent()
}

struct WindowResizeWeightChange {
    let node: TreeNode
    let orientation: Orientation
    let weight: CGFloat
}

struct WindowResizePreviewWeightMap {
    private var weights: [WindowResizeWeightKey: CGFloat] = [:]
    private var nodes: [ObjectIdentifier: TreeNode] = [:]

    @MainActor
    var changes: [WindowResizeWeightChange] {
        weights.compactMap { key, weight in
            guard let node = nodes[key.nodeId] else { return nil }
            return WindowResizeWeightChange(node: node, orientation: key.orientation, weight: weight)
        }
    }

    mutating func set(_ weight: CGFloat, for node: TreeNode, orientation: Orientation) {
        let nodeId = ObjectIdentifier(node)
        weights[WindowResizeWeightKey(nodeId: nodeId, orientation: orientation)] = weight
        nodes[nodeId] = node
    }

    @MainActor
    func weight(for node: TreeNode, orientation: Orientation) -> CGFloat {
        weights[WindowResizeWeightKey(nodeId: ObjectIdentifier(node), orientation: orientation)] ??
            node.getWeight(orientation)
    }
}

private struct WindowResizeWeightKey: Hashable {
    let nodeId: ObjectIdentifier
    let orientation: Orientation
}

@MainActor
func proposedResizeWeightMap(_ window: Window, rect: Rect) -> WindowResizePreviewWeightMap? {
    resizeProposal(window, rect: rect)?.weights
}

@MainActor
func resizeProposal(_ window: Window, rect: Rect) -> (weights: WindowResizePreviewWeightMap, rect: Rect)? {
    guard window.parent is TilingContainer else { return nil }
    guard let lastAppliedLayoutRect = window.lastAppliedLayoutPhysicalRect else { return nil }
    var weightMap = WindowResizePreviewWeightMap()
    let (lParent, lOwnIndex) = window.closestParent(hasChildrenInDirection: .left, withLayout: .tiles) ?? (nil, nil)
    let (dParent, dOwnIndex) = window.closestParent(hasChildrenInDirection: .down, withLayout: .tiles) ?? (nil, nil)
    let (uParent, uOwnIndex) = window.closestParent(hasChildrenInDirection: .up, withLayout: .tiles) ?? (nil, nil)
    let (rParent, rOwnIndex) = window.closestParent(hasChildrenInDirection: .right, withLayout: .tiles) ?? (nil, nil)
    let table: [(CGFloat, TilingContainer?, Int?, Int?)] = [
        (lastAppliedLayoutRect.minX - rect.minX, lParent, 0,                        lOwnIndex),               // Horizontal, to the left of the window
        (rect.maxY - lastAppliedLayoutRect.maxY, dParent, dOwnIndex.map { $0 + 1 }, dParent?.children.count), // Vertical, to the down of the window
        (lastAppliedLayoutRect.minY - rect.minY, uParent, 0,                        uOwnIndex),               // Vertical, to the up of the window
        (rect.maxX - lastAppliedLayoutRect.maxX, rParent, rOwnIndex.map { $0 + 1 }, rParent?.children.count), // Horizontal, to the right of the window
    ]
    var minX = rect.minX
    var maxX = rect.maxX
    var minY = rect.minY
    var maxY = rect.maxY
    for (edge, entry) in table.enumerated() {
        let (diff, parent, startIndex, pastTheEndIndex) = entry
        if let parent, let startIndex, let pastTheEndIndex, pastTheEndIndex - startIndex > 0 && abs(diff) > 5 { // 5 pixels should be enough to fight with accumulated floating precision error
            let orientation = parent.orientation
            let growingNodes = window.parentsWithSelf
                .prefix(while: { $0 != parent })
                .filter {
                    let parent = $0.parent as? TilingContainer
                    return parent?.orientation == orientation && parent?.layout == .tiles
                }
            let siblings = parent.children[startIndex ..< pastTheEndIndex]
            let minimumDiff = growingNodes.map { $0.resizeMinimumWeight - $0.getWeightBeforeResize(orientation) }.max() ?? 0
            let maximumDiff = siblings.map {
                ($0.getWeightBeforeResize(orientation) - $0.resizeMinimumWeight) * CGFloat(siblings.count)
            }.min() ?? 0
            let boundedDiff = min(max(diff, min(0, minimumDiff)), max(0, maximumDiff))
            switch edge {
                case 0: minX = lastAppliedLayoutRect.minX - boundedDiff
                case 1: maxY = lastAppliedLayoutRect.maxY + boundedDiff
                case 2: minY = lastAppliedLayoutRect.minY - boundedDiff
                default: maxX = lastAppliedLayoutRect.maxX + boundedDiff
            }
            let siblingDiff = boundedDiff / CGFloat(siblings.count)
            growingNodes.forEach {
                weightMap.set($0.getWeightBeforeResize(orientation) + boundedDiff, for: $0, orientation: orientation)
            }
            for sibling in parent.children[startIndex ..< pastTheEndIndex] {
                weightMap.set(sibling.getWeightBeforeResize(orientation) - siblingDiff, for: sibling, orientation: orientation)
            }
        }
    }
    return (weightMap, Rect(topLeftX: minX, topLeftY: minY, width: maxX - minX, height: maxY - minY))
}

extension TreeNode {
    @MainActor
    func getWeightBeforeResize(_ orientation: Orientation) -> CGFloat {
        let currentWeight = getWeight(orientation) // Check assertions
        return getUserData(key: adaptiveWeightBeforeResizeWithMouseKey)
            ?? (lastAppliedLayoutVirtualRect?.getDimension(orientation) ?? currentWeight)
            .also { putUserData(key: adaptiveWeightBeforeResizeWithMouseKey, data: $0) }
    }

    func resetResizeWeightBeforeResizeRecursive() {
        cleanUserData(key: adaptiveWeightBeforeResizeWithMouseKey)
        for child in children {
            child.resetResizeWeightBeforeResizeRecursive()
        }
    }
}
