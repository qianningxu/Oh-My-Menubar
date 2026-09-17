import CoreGraphics

@MainActor
func destinationFromWindowDropIntent(
    _ resolution: WindowDropIntentResolution,
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    func intentOverlayDestination(
        _ destination: WindowDragIntentDestination,
        highlightsActiveZone: Bool = true
    ) -> WindowDragIntentDestination {
        let activeZone = highlightsActiveZone ? resolution.intent.zone : nil
        return destination.replacingIntentPreview(
            containerRect: resolution.targetFrame,
            previewRect: windowDropIntentActivePreviewRect(for: resolution),
            interactionRect: resolution.targetFrame,
            zones: windowDropIntentPreviewZones(for: resolution, activeZone: activeZone)
        )
        .withDropIntentOverlay(WindowDropIntentOverlayModel(
            targetFrame: resolution.targetFrame,
            activeZone: activeZone,
            cornerRadius: resolution.targetCornerRadius.map(CGFloat.init)
        ))
    }

    switch resolution.intent.zone {
        case .tab:
            if let destination = sameTabGroupReturnDestination(
                resolution: resolution,
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                detachOrigin: detachOrigin,
            ) {
                return intentOverlayDestination(destination)
            }
            guard config.windowTabs.enabled,
                  isWindowDragIntentKindEnabled(.tabStack(targetWindowId: targetWindow.windowId)),
                  !shouldSuppressSameTabGroupTabDestination(
                      sourceWindow: sourceWindow,
                      targetWindow: targetWindow,
                      detachOrigin: detachOrigin
                  )
            else { return nil }
            return intentOverlayDestination(WindowDragIntentDestination(
                kind: .tabStack(targetWindowId: targetWindow.windowId),
                previewContainerRect: resolution.targetFrame,
                previewRect: windowDropIntentActivePreviewRect(for: resolution),
                interactionRect: resolution.targetFrame,
                title: "Insert Into Tabs",
                subtitle: "Drop in the top zone to add this window",
                previewStyle: .tabInsert,
                previewGeometry: .tabStrip,
                isGroup: false,
            ))
        case .middle:
            // A composed tab group has no meaningful centre-swap operation.
            // Keep the full guide visible while the pointer is here, but make
            // the centre cell neutral and make mouse-up a no-op.
            if subject == .group {
                return intentOverlayDestination(WindowDragIntentDestination(
                    kind: .sidebarHover,
                    previewContainerRect: resolution.targetFrame,
                    previewRect: resolution.targetFrame,
                    interactionRect: resolution.targetFrame,
                    title: "",
                    subtitle: "",
                    previewStyle: .workspaceMove,
                    previewGeometry: .rounded,
                    isGroup: true,
                ), highlightsActiveZone: false)
            }
            if let destination = sameTabGroupReturnDestination(
                resolution: resolution,
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                detachOrigin: detachOrigin,
            ) {
                return intentOverlayDestination(destination)
            }
            guard let destination = swapDestination(
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                detachOrigin: detachOrigin,
            ) else { return nil }
            return intentOverlayDestination(destination)
        case .left, .right, .top, .bottom:
            guard let position = resolution.intent.zone.stackSplitPosition else { return nil }
            guard let destination = stackSplitDestination(
                sourceWindow: sourceWindow,
                targetWindow: targetWindow,
                subject: subject,
                position: position,
                detachOrigin: detachOrigin,
            ) else { return nil }
            return intentOverlayDestination(destination)
    }
}

@MainActor
private func sameTabGroupReturnDestination(
    resolution: WindowDropIntentResolution,
    sourceWindow: Window,
    targetWindow: Window,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    guard subject == .window,
          detachOrigin == .tabStrip,
          config.windowTabs.enabled,
          let sourceParent = sourceWindow.parent as? TilingContainer,
          sourceParent.layout == .tabGroup,
          targetWindow.parent === sourceParent
    else { return nil }
    return WindowDragIntentDestination(
        kind: .reorderTab(windowId: sourceWindow.windowId, targetIndex: sourceWindow.ownIndex ?? 0),
        previewContainerRect: resolution.targetFrame,
        previewRect: windowDropIntentActivePreviewRect(for: resolution),
        interactionRect: resolution.targetFrame,
        title: "Return To Tabs",
        subtitle: "Drop to keep this tab in the current group",
        previewStyle: .tabInsert,
        previewGeometry: .tabStrip,
        isGroup: false,
    )
}

func windowDropIntentActivePreviewRect(for resolution: WindowDropIntentResolution) -> Rect {
    if let position = resolution.intent.zone.stackSplitPosition,
       let splitPreviewRect = resolution.targetFrame.stackSplitPreviewRect(position: position)
    {
        return splitPreviewRect
    }
    return resolution.zones.first { $0.zone == resolution.intent.zone }?.frame ?? resolution.targetFrame
}

func windowDropIntentPreviewZones(
    for resolution: WindowDropIntentResolution
) -> [WindowDragIntentPreviewZone] {
    windowDropIntentPreviewZones(for: resolution, activeZone: resolution.intent.zone)
}

func windowDropIntentPreviewZones(
    for resolution: WindowDropIntentResolution,
    activeZone: WindowDropZone?
) -> [WindowDragIntentPreviewZone] {
    resolution.zones.map { zone in
        let previewRect = zone.zone.stackSplitPosition
            .flatMap { resolution.targetFrame.stackSplitPreviewRect(position: $0) }
            ?? zone.frame
        return WindowDragIntentPreviewZone(
            rect: previewRect,
            style: zone.zone.previewStyle,
            geometry: zone.zone.previewGeometry,
            isActive: zone.zone == activeZone
        )
    }
}

private extension WindowDropZone {
    var previewStyle: WindowTabDropPreviewStyle {
        switch self {
            case .tab:
                .tabInsert
            case .left, .right, .top, .bottom:
                .stackSplit
            case .middle:
                .swap
        }
    }

    var previewGeometry: WindowTabDropPreviewGeometry {
        switch self {
            case .tab:
                .tabStrip
            case .left:
                .splitLeft
            case .right:
                .splitRight
            case .top:
                .splitAbove
            case .bottom:
                .splitBelow
            case .middle:
                .rounded
        }
    }
}

@MainActor
func resolveWindowDropIntent(
    sourceWindow: Window,
    targetWindow: Window,
    targetNode: TreeNode,
    mouseLocation: CGPoint,
) -> WindowDropIntentResolution? {
    guard let targetFrame = targetNode.windowDragVisibleRect else { return nil }
    return WindowDropIntentResolver().resolve(
        sourceWindowId: sourceWindow.windowId,
        targetWindowId: targetWindow.windowId,
        pointer: mouseLocation,
        targetFrame: targetFrame,
    )
}
