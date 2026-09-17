import AppKit

struct WorkspaceSidebarPanelLayout {
    let frame: NSRect
    let expandedWidth: CGFloat
    let collapsedWidth: CGFloat
    let metrics: WorkspaceSidebarSideAreaMetrics
}

extension WorkspaceSidebarPanel {
    func currentSidebarPanelLayout() -> WorkspaceSidebarPanelLayout? {
        currentSidebarPanelLayout(on: workspaceSidebarLocalPanelMonitor())
    }

    func currentSidebarPanelLayout(on monitor: Monitor) -> WorkspaceSidebarPanelLayout? {
        guard TrayMenuModel.shared.isEnabled,
              config.workspaceSidebar.enabled,
              let screen = workspaceSidebarPanelScreen(for: monitor)
        else { return nil }
        guard !shouldSuppressWorkspaceSidebarForFullscreenContent() else { return nil }

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let contentSize = projectBarContentSize == .zero
            ? CGSize(
                width: max(fittingSize.width, standardGap * 24),
                height: max(fittingSize.height, WinMuxBarStyle.projectBarHeight - WinMuxBarStyle.projectTabsBarOuterInset)
            )
            : projectBarContentSize
        let frame = workspaceSidebarFloatingProjectBarPanelFrame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            barSize: contentSize,
            extraWidth: projectActionMenuPresentationExtraWidth,
            extraHeight: projectMenuPresentationExtraHeight,
            contentOutset: WinMuxBarStyle.workspaceBarShadowOutset,
            notchLeadingEdge: screen.auxiliaryTopLeftArea?.maxX,
        )

        return WorkspaceSidebarPanelLayout(
            frame: frame,
            expandedWidth: frame.width,
            collapsedWidth: frame.width,
            metrics: .standard,
        )
    }

    func workspaceSidebarPanelScreen() -> NSScreen? {
        workspaceSidebarPanelScreen(for: workspaceSidebarLocalPanelMonitor())
    }

    func workspaceSidebarPanelScreen(for monitor: Monitor) -> NSScreen? {
        workspaceSidebarScreen(for: monitor)
    }

    func workspaceSidebarLocalPanelMonitor() -> Monitor {
        workspaceSidebarMonitor(forScopeId: monitorScopeId) ?? workspaceSidebarResolvedPanelMonitor()
    }
}

func workspaceSidebarScreen(for monitor: Monitor) -> NSScreen? {
    NSScreen.screens.getOrNil(
        atIndex: monitor.monitorAppKitNsScreenScreensId - 1
    ) ?? NSScreen.screens.first
}

@MainActor
func workspaceSidebarTopBarHeight(for screen: NSScreen) -> CGFloat {
    let nativeMenuBarHeight = max(
        screen.frame.maxY - screen.visibleFrame.maxY,
        NSStatusBar.system.thickness,
    )
    return max(nativeMenuBarHeight, screen.safeAreaInsets.top)
}

@MainActor
func workspaceSidebarTopBarRegion(for screen: NSScreen, barHeight: CGFloat? = nil) -> NSRect {
    let resolvedBarHeight = max(barHeight ?? workspaceSidebarTopBarHeight(for: screen), 1)
    return workspaceSidebarTopBarRegionFrame(
        screenFrame: screen.frame,
        auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
        barHeight: resolvedBarHeight,
    )
}

@MainActor
func menuBarStatusWidgetRegion(for screen: NSScreen, barHeight: CGFloat? = nil) -> NSRect {
    let resolvedBarHeight = max(barHeight ?? workspaceSidebarTopBarHeight(for: screen), 1)
    return menuBarStatusWidgetRegionFrame(
        screenFrame: screen.frame,
        auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
        barHeight: resolvedBarHeight,
    )
}

@MainActor
func workspaceSidebarProjectBarVisibleReservation(for _: Monitor) -> CGFloat {
    guard TrayMenuModel.shared.isEnabled, config.workspaceSidebar.enabled,
          !shouldSuppressWorkspaceSidebarForFullscreenContent() else { return 0 }
    return workspaceSidebarProjectBarVisibleReservation(
        autoHideEnabled: workspaceSidebarAutoHidePreference()
    )
}

func workspaceSidebarProjectBarVisibleReservation(autoHideEnabled _: Bool) -> CGFloat {
    0
}

func workspaceSidebarTopBarRegionFrame(
    screenFrame: NSRect,
    auxiliaryTopLeftArea _: NSRect?,
    barHeight: CGFloat,
) -> NSRect {
    let resolvedBarHeight = max(barHeight, 1)
    // Preserve the full-width menu-adjacent region for compatibility with
    // callers that still use this geometry independently of the bottom bar.
    return NSRect(
        x: screenFrame.minX,
        y: screenFrame.maxY - resolvedBarHeight - WinMuxBarStyle.projectBarHeight,
        width: screenFrame.width,
        height: WinMuxBarStyle.projectBarHeight,
    )
}

func menuBarStatusWidgetRegionFrame(
    screenFrame: NSRect,
    auxiliaryTopRightArea _: NSRect?,
    barHeight: CGFloat,
) -> NSRect {
    let resolvedBarHeight = max(barHeight, 1)
    // The balanced Widget bar owns the full horizontal strip. Its leading and
    // trailing groups naturally leave the camera/notch area clear.
    return NSRect(
        x: screenFrame.minX,
        y: screenFrame.maxY - resolvedBarHeight,
        width: screenFrame.width,
        height: resolvedBarHeight,
    )
}

func workspaceSidebarFloatingProjectBarPanelFrame(
    screenFrame: NSRect,
    visibleFrame: NSRect,
    barSize: CGSize,
    extraWidth: CGFloat = 0,
    extraHeight: CGFloat = 0,
    contentOutset: CGFloat = 0,
    notchLeadingEdge: CGFloat? = nil,
) -> NSRect {
    let horizontalMargin = WinMuxSpacing.comfortable
    let maximumWidth = max(screenFrame.width - horizontalMargin * 2, 1)
    let width = min(max(barSize.width + max(extraWidth, 0), 1), maximumWidth)
    let height = max(barSize.height + max(extraHeight, 0), 1)
    let outset = max(contentOutset, 0)
    let centeredX = screenFrame.midX - width / 2
    let notchAdjacentX = notchLeadingEdge.map {
        $0 - WinMuxSpacing.compact - max(width - outset * 2, 1) - outset
    }
    let x = min(
        max(notchAdjacentX ?? centeredX, screenFrame.minX - outset),
        screenFrame.maxX - width + outset
    )
    let menuBarHeight = max(screenFrame.maxY - visibleFrame.maxY, 1)
    let visualHeight = max(height - outset * 2, 1)
    let visualY = visibleFrame.maxY + (menuBarHeight - visualHeight) / 2
    return NSRect(x: x, y: visualY - outset, width: width, height: height)
}

func workspaceSidebarFloatingProjectBarVisualFrame(
    panelFrame: NSRect,
    contentOutset: CGFloat = WinMuxBarStyle.workspaceBarShadowOutset
) -> NSRect {
    panelFrame.insetBy(dx: max(contentOutset, 0), dy: max(contentOutset, 0))
}

func workspaceSidebarPanelFrame(
    screenFrame: NSRect,
    visibleFrame: NSRect,
    width: CGFloat,
    extraTopReserveHeight: CGFloat,
) -> NSRect {
    let visibleMinX = min(max(visibleFrame.minX, screenFrame.minX), screenFrame.maxX - 1)
    let visibleMaxX = min(max(visibleFrame.maxX, visibleMinX + 1), screenFrame.maxX)
    let clampedWidth = min(max(width, 1), max(visibleMaxX - visibleMinX, 1))
    let visibleMaxY = min(max(visibleFrame.maxY, screenFrame.minY + 1), screenFrame.maxY)
    let visibleMinY = min(max(visibleFrame.minY, screenFrame.minY), visibleMaxY - 1)
    let builtInTopInset = max(screenFrame.maxY - visibleMaxY, 0)
    let additionalTopReserve = max(extraTopReserveHeight - builtInTopInset, 0)
    let topReserve = min(max(additionalTopReserve, 0), max(visibleMaxY - visibleMinY - 1, 0))
    let maxY = max(visibleMaxY - topReserve, visibleMinY + 1)
    let height = max(maxY - visibleMinY, 1)
    return NSRect(
        x: visibleMinX,
        y: visibleMinY,
        width: clampedWidth,
        height: height,
    )
}
