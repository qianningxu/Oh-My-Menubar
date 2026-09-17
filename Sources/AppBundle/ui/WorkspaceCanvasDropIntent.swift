import AppKit

@MainActor
func workspaceCanvasDropIntent(
    sourceWorkspaceName: String,
    screenPoint: CGPoint
) -> (action: WorkspaceCanvasDropAction?, overlay: WindowDropIntentOverlayModel)? {
    guard WorkspaceSidebarPanel.panel(containing: screenPoint) == nil,
          let sourceWorkspace = Workspace.existing(byName: sourceWorkspaceName)
    else { return nil }
    let targetWorkspace = screenPoint.monitorApproximation.activeWorkspace
    guard targetWorkspace != sourceWorkspace else { return nil }
    // A workspace tab is dropped onto one visible window, never an entire
    // workspace. Resolving that window here keeps the guide to a single
    // frame when the destination workspace is tiled.
    guard let targetWindow = screenPoint.findWindowDragTarget(
        in: targetWorkspace.rootTilingContainer
    ),
    let targetFrame = targetWindow.moveNode.windowDragVisibleRect,
    let zone = WindowIntentZoneBuilder.zone(at: screenPoint, in: targetFrame)
    else { return nil }
    let action = workspaceCanvasDropAction(for: zone, targetWindowId: targetWindow.windowId)
    return (
        action,
        WindowDropIntentOverlayModel(
            targetFrame: targetFrame,
            // Middle remains visible as a neutral guide cell. It must not
            // receive the active hover treatment because workspace tab
            // drags have no centre-swap operation.
            activeZone: action == nil ? nil : zone,
            cornerRadius: nil
        )
    )
}

enum WorkspaceCanvasDropAction: Equatable {
    case tabStack(targetWindowId: UInt32)
    case split(WindowStackSplitPosition)
}

private func workspaceCanvasDropAction(
    for zone: WindowDropZone,
    targetWindowId: UInt32
) -> WorkspaceCanvasDropAction? {
    switch zone {
        case .tab:
            .tabStack(targetWindowId: targetWindowId)
        case .left, .right, .top, .bottom:
            zone.stackSplitPosition.map(WorkspaceCanvasDropAction.split)
        case .middle:
            nil
    }
}
