import AppKit
import Common

extension Workspace {
    @MainActor
    func layoutWorkspace() async throws {
        if isEffectivelyEmpty { return }
        let rect = workspaceMonitor.visibleRectPaddedByOuterGaps
        let context = LayoutContext(self)
        for window in rootTilingContainer.allLeafWindowsRecursive {
            if let macWindow = window as? MacWindow, window.minimumSize == nil {
                window.minimumSize = try await macWindow.macApp.measureMinimumSize(window.windowId)
                try checkCancellation()
            }
        }
        if let tabGroup = rootTilingContainer.allTabbedContainersRecursive.first(where: \.hasFullscreenTab) {
            lastAppliedLayoutPhysicalRect = rect
            lastAppliedLayoutVirtualRect = rect
            rootTilingContainer.lastAppliedLayoutPhysicalRect = rect
            rootTilingContainer.lastAppliedLayoutVirtualRect = rect
            tabGroup.lastAppliedLayoutPhysicalRect = rect
            tabGroup.lastAppliedLayoutVirtualRect = rect
            try await hideAllWindowsExcept(tabGroup)
            try await tabGroup.layoutRecursive(rect.topLeftCorner, width: rect.width, height: rect.height, virtual: rect, context)
            return
        }
        if let fullscreenWindow = rootTilingContainer.mostRecentWindowRecursive, fullscreenWindow.isFullscreen {
            lastAppliedLayoutPhysicalRect = rect
            lastAppliedLayoutVirtualRect = rect
            rootTilingContainer.lastAppliedLayoutPhysicalRect = rect
            rootTilingContainer.lastAppliedLayoutVirtualRect = rect
            try await hideAllWindowsExcept(fullscreenWindow)
            fullscreenWindow.lastAppliedLayoutVirtualRect = rect
            fullscreenWindow.lastAppliedLayoutPhysicalRect = nil
            fullscreenWindow.layoutFullscreen(context)
            return
        }
        // If monitors are aligned vertically and the monitor below has smaller width, then macOS may not allow the
        // window on the upper monitor to take full width. rect.height - 1 resolves this problem
        // But I also faced this problem in monitors horizontal configuration. ¯\_(ツ)_/¯
        let bottomAdjustment: CGFloat = config.workspaceSidebar.enabled ? 0 : 1
        try await layoutRecursive(rect.topLeftCorner, width: rect.width, height: rect.height - bottomAdjustment, virtual: rect, context)
    }
}

extension TreeNode {
    @MainActor
    fileprivate func layoutRecursive(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        try checkCancellation()
        guard !TrayMenuModel.shared.isEnabled || context.workspace.isVisible else { return }
        // AX calls below can suspend this MainActor task. A newer refresh may move or
        // detach the subtree before this layout pass resumes.
        guard self === context.workspace || nodeWorkspace === context.workspace else { return }
        let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
        switch nodeCases {
            case .workspace(let workspace):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                try await workspace.rootTilingContainer.layoutRecursive(point, width: width, height: height, virtual: virtual, context)
                for window in workspace.children.filterIsInstance(of: Window.self) {
                    window.lastAppliedLayoutPhysicalRect = nil
                    window.lastAppliedLayoutVirtualRect = nil
                    try await window.layoutFloatingWindow(context)
                }
            case .window(let window):
                if window.windowId != currentlyManipulatedWithMouseWindowId || isPinnedDraggedWindow(window.windowId) {
                    let previousPhysicalRect = lastAppliedLayoutPhysicalRect
                    lastAppliedLayoutVirtualRect = virtual
                    let isFullscreenTab = window.nearestWindowTabGroup?.hasFullscreenTab == true
                    if window.isFullscreen && !isFullscreenTab && window == context.workspace.rootTilingContainer.mostRecentWindowRecursive {
                        lastAppliedLayoutPhysicalRect = nil
                        window.layoutFullscreen(context)
                    } else {
                        lastAppliedLayoutPhysicalRect = physicalRect
                        if !isFullscreenTab {
                            window.isFullscreen = false
                        }
                        // A matching cached target is not evidence the window
                        // is onscreen: a cancelled hide/frame job may have moved
                        // it since the last observation. Verify before reusing it.
                        let sidebarInset = context.workspace.workspaceMonitor.workspaceSidebarInset
                        let actualRect = sidebarInset > 0 ? try await window.getAxRect() : window.lastKnownActualRect
                        try checkCancellation()
                        guard !TrayMenuModel.shared.isEnabled || context.workspace.isVisible else { return }
                        if shouldSynchronouslyApplySidebarProtectedFrame(
                            sidebarInset: sidebarInset,
                            actualRect: actualRect,
                            targetRect: physicalRect
                        ), let macWindow = window as? MacWindow {
                            try await macWindow.setAxFrameBlocking(point, CGSize(width: width, height: height))
                            _ = try await macWindow.getAxRect()
                        } else if !canReuseLastAppliedWindowFrame(previousPhysicalRect: previousPhysicalRect, nextPhysicalRect: physicalRect) {
                            window.setAxFrame(point, CGSize(width: width, height: height))
                        }
                    }
                }
            case .tilingContainer(let container):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                if container.usesWindowTabBehavior {
                    debugFocusLog("layoutRecursive tabContainer=\(ObjectIdentifier(container)) physicalRect=\(physicalRect) virtualRect=\(virtual)")
                }
                switch container.layout {
                    case .tiles:
                        try await container.layoutTiles(point, width: width, height: height, virtual: virtual, context)
                    case .tabGroup:
                        try await container.layoutTabGroup(point, width: width, height: height, virtual: virtual, context)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return // Nothing to do for weirdos
        }
    }
}

func shouldSynchronouslyApplySidebarProtectedFrame(
    sidebarInset: CGFloat,
    actualRect: Rect?,
    targetRect: Rect,
    tolerance: CGFloat = 1
) -> Bool {
    guard sidebarInset > 0 else { return false }
    guard let actualRect else { return true }
    return abs(actualRect.topLeftX - targetRect.topLeftX) > tolerance ||
        abs(actualRect.topLeftY - targetRect.topLeftY) > tolerance ||
        abs(actualRect.width - targetRect.width) > tolerance ||
        abs(actualRect.height - targetRect.height) > tolerance
}

private func canReuseLastAppliedWindowFrame(previousPhysicalRect: Rect?, nextPhysicalRect: Rect) -> Bool {
    guard refreshSessionEvent?.canReuseLastAppliedWindowFrames == true else { return false }
    guard let previousPhysicalRect else { return false }
    return previousPhysicalRect.topLeftX == nextPhysicalRect.topLeftX &&
        previousPhysicalRect.topLeftY == nextPhysicalRect.topLeftY &&
        previousPhysicalRect.width == nextPhysicalRect.width &&
        previousPhysicalRect.height == nextPhysicalRect.height
}

private struct LayoutContext {
    let workspace: Workspace
    let resolvedGaps: ResolvedGaps

    @MainActor
    init(_ workspace: Workspace) {
        self.workspace = workspace
        self.resolvedGaps = ResolvedGaps(
            gaps: config.gaps,
            monitor: workspace.workspaceMonitor,
            canvasGap: config.workspaceSidebar.enabled ? Int(WinMuxSpacing.comfortable) : nil
        )
    }
}

extension Window {
    @MainActor
    fileprivate func layoutFloatingWindow(_ context: LayoutContext) async throws {
        let workspace = context.workspace
        let windowRect = try await getAxRect() // Probably not idempotent
        let currentMonitor = windowRect?.center.monitorApproximation
        if let currentMonitor, let windowRect, workspace != currentMonitor.activeWorkspace {
            let windowTopLeftCorner = windowRect.topLeftCorner
            let xProportion = (windowTopLeftCorner.x - currentMonitor.visibleRect.topLeftX) / currentMonitor.visibleRect.width
            let yProportion = (windowTopLeftCorner.y - currentMonitor.visibleRect.topLeftY) / currentMonitor.visibleRect.height

            let workspaceRect = workspace.workspaceMonitor.visibleRect
            var newX = workspaceRect.topLeftX + xProportion * workspaceRect.width
            var newY = workspaceRect.topLeftY + yProportion * workspaceRect.height

            let windowWidth = windowRect.width
            let windowHeight = windowRect.height
            newX = newX.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowWidth))
            newY = newY.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowHeight))

            setAxFrame(CGPoint(x: newX, y: newY), nil)
        }
        if isFullscreen {
            layoutFullscreen(context)
            isFullscreen = false
        }
    }

    @MainActor
    fileprivate func layoutFullscreen(_ context: LayoutContext) {
        let monitorRect = noOuterGapsInFullscreen
            ? context.workspace.workspaceMonitor.visibleRect
            : context.workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        setAxFrame(monitorRect.topLeftCorner, CGSize(width: monitorRect.width, height: monitorRect.height))
    }
}

extension TilingContainer {
    @MainActor
    fileprivate func layoutTiles(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        var point = point
        var virtualPoint = virtual.topLeftCorner

        let weights = constrainedTileWeights(
            proposed: children.map { $0.getWeight(orientation) },
            minimums: minimumTileWeights(gaps: context.resolvedGaps),
            available: orientation == .h ? width : height
        )
        let lastIndex = children.indices.last
        for (i, child) in children.enumerated() {
            guard nodeWorkspace === context.workspace, child.parent === self else { return }
            let childWeight = weights[i]
            child.setWeight(orientation, childWeight)
            let rawGap = context.resolvedGaps.inner.get(orientation).toDouble()
            // Gaps. Consider 4 cases:
            // 1. Multiple children. Layout first child
            // 2. Multiple children. Layout last child
            // 3. Multiple children. Layout child in the middle
            // 4. Single child   let rawGap = gaps.inner.get(orientation).toDouble()
            let gap = rawGap - (i == 0 ? rawGap / 2 : 0) - (i == lastIndex ? rawGap / 2 : 0)
            try await child.layoutRecursive(
                i == 0 ? point : point.addingOffset(orientation, rawGap / 2),
                width: orientation == .h ? childWeight - gap : width,
                height: orientation == .v ? childWeight - gap : height,
                virtual: Rect(
                    topLeftX: virtualPoint.x,
                    topLeftY: virtualPoint.y,
                    width: orientation == .h ? childWeight : width,
                    height: orientation == .v ? childWeight : height,
                ),
                context,
            )
            virtualPoint = orientation == .h ? virtualPoint.addingXOffset(childWeight) : virtualPoint.addingYOffset(childWeight)
            point = orientation == .h ? point.addingXOffset(childWeight) : point.addingYOffset(childWeight)
        }
    }

    @MainActor
    fileprivate func layoutTabGroup(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        if usesWindowTabBehavior {
            let tabBarHeight = showsWindowTabs ? windowTabBarHeight : 0
            let shellHorizontalInset = showsWindowTabs ? windowTabGroupShellHorizontalInset() : 0
            let shellTopInset = showsWindowTabs ? windowTabGroupShellTopInset() : 0
            let shellBottomInset = showsWindowTabs ? windowTabGroupShellBottomInset() : 0
            let contentPoint = point + CGPoint(x: shellHorizontalInset, y: tabBarHeight + shellTopInset)
            let contentWidth = max(width - shellHorizontalInset * 2, 0)
            let contentHeight = max(height - tabBarHeight - shellTopInset - shellBottomInset, 0)
            let contentVirtual = Rect(
                topLeftX: virtual.topLeftX + shellHorizontalInset,
                topLeftY: virtual.topLeftY + tabBarHeight + shellTopInset,
                width: max(virtual.width - shellHorizontalInset * 2, 0),
                height: max(virtual.height - tabBarHeight - shellTopInset - shellBottomInset, 0),
            )
            guard let activeChild = mostRecentChild else { return }

            // Switch tabs by placing the newly active child first, then parking the old visible tabs.
            try await activeChild.layoutRecursive(
                contentPoint,
                width: contentWidth,
                height: contentHeight,
                virtual: contentVirtual,
                context,
            )
            for child in children where child != activeChild {
                try await child.hideTabbedWindows(context.workspace)
            }
            return
        }

        guard let mruIndex: Int = mostRecentChild?.ownIndex else { return }
        for (index, child) in children.enumerated() {
            let padding = CGFloat(config.tabGroupPadding)
            let (lPadding, rPadding): (CGFloat, CGFloat) = switch index {
                case 0 where children.count == 1: (0, 0)
                case 0:                           (0, padding)
                case children.indices.last:       (padding, 0)
                case mruIndex - 1:                (0, 2 * padding)
                case mruIndex + 1:                (2 * padding, 0)
                default:                          (padding, padding)
            }
            switch orientation {
                case .h:
                    try await child.layoutRecursive(
                        point + CGPoint(x: lPadding, y: 0),
                        width: width - rPadding - lPadding,
                        height: height,
                        virtual: virtual,
                        context,
                    )
                case .v:
                    try await child.layoutRecursive(
                        point + CGPoint(x: 0, y: lPadding),
                        width: width,
                        height: height - lPadding - rPadding,
                        virtual: virtual,
                        context,
                    )
            }
        }
    }
}

extension TreeNode {
    @MainActor
    fileprivate func hideTabbedWindows(_ workspace: Workspace) async throws {
        switch nodeCases {
            case .window(let window):
                window.lastAppliedLayoutPhysicalRect = nil
                window.lastAppliedLayoutVirtualRect = nil
                if let macWindow = window as? MacWindow {
                    try await macWindow.hideInCorner(.bottomRightCorner)
                }
            case .tilingContainer(let container):
                for child in container.children {
                    try await child.hideTabbedWindows(workspace)
                }
            case .workspace, .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return
        }
    }

    @MainActor
    fileprivate func hideAllWindowsExcept(_ targetWindow: Window) async throws {
        switch nodeCases {
            case .window(let window):
                guard window != targetWindow else { return }
                window.lastAppliedLayoutPhysicalRect = nil
                window.lastAppliedLayoutVirtualRect = nil
                if let macWindow = window as? MacWindow {
                    try await macWindow.hideInCorner(.bottomRightCorner)
                }
            case .tilingContainer(let container):
                for child in container.children {
                    try await child.hideAllWindowsExcept(targetWindow)
                }
            case .workspace(let workspace):
                for child in workspace.children {
                    try await child.hideAllWindowsExcept(targetWindow)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return
        }
    }

    @MainActor
    fileprivate func hideAllWindowsExcept(_ targetNode: TreeNode) async throws {
        if self === targetNode { return }
        switch nodeCases {
            case .window(let window):
                window.lastAppliedLayoutPhysicalRect = nil
                window.lastAppliedLayoutVirtualRect = nil
                if let macWindow = window as? MacWindow {
                    try await macWindow.hideInCorner(.bottomRightCorner)
                }
            case .tilingContainer(let container):
                for child in container.children {
                    try await child.hideAllWindowsExcept(targetNode)
                }
            case .workspace(let workspace):
                for child in workspace.children {
                    try await child.hideAllWindowsExcept(targetNode)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return
        }
    }
}
