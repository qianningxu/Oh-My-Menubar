@MainActor
func normalizeLayoutReason() async throws {
    for workspace in Workspace.all {
        let windows: [Window] = workspace.allLeafWindowsRecursive
        try await _normalizeLayoutReason(workspace: workspace, windows: windows)
    }
    try await _normalizeLayoutReason(workspace: focus.workspace, windows: macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self))
    try await _normalizeLayoutReason(workspace: focus.workspace, windows: globalFloatingWindowsContainer.allLeafWindowsRecursive)
    try await validateStillPopups()
}

/// Normalizes only the windows refreshed from one AX creation notification.
/// This keeps native fullscreen/minimize handling correct without making a
/// new window wait for every other process to be queried.
@MainActor
func normalizeLayoutReason(for windows: [Window]) async throws {
    let windowIds = Set(windows.map(\.windowId))
    for workspace in Workspace.all {
        let workspaceWindows = workspace.allLeafWindowsRecursive.filter {
            windowIds.contains($0.windowId)
        }
        try await _normalizeLayoutReason(workspace: workspace, windows: workspaceWindows)
    }
    try await validateStillPopups(windowIds: windowIds)
}

@MainActor
private func validateStillPopups(windowIds: Set<UInt32>? = nil) async throws {
    for node in macosPopupWindowsContainer.children {
        guard let popup = node as? MacWindow else { continue }
        guard windowIds?.contains(popup.windowId) ?? true else { continue }
        let windowLevel = try await getWindowLevel(for: popup.windowId)
        if try await popup.isWindowHeuristic(windowLevel) {
            try await popup.relayoutWindow(on: focus.workspace)
            try await tryOnWindowDetected(popup)
        }
    }
}

@MainActor
private func _normalizeLayoutReason(workspace: Workspace, windows: [Window]) async throws {
    for window in windows {
        if normalizeSystemOverlayWindow(window, level: try await getWindowLevel(for: window.windowId)) {
            continue
        }
        let isMacosFullscreen = try await window.isMacosFullscreen
        let isMacosMinimized = try await (!isMacosFullscreen).andAsync { @MainActor @Sendable in try await window.isMacosMinimized }
        let isMacosWindowOfHiddenApp = !isMacosFullscreen && !isMacosMinimized &&
            !config.automaticallyUnhideMacosHiddenApps && window.macAppUnsafe.nsApp.isHidden
        switch window.layoutReason {
            case .standard:
                guard window.parent != nil else { continue }
                switch true {
                    case isMacosFullscreen:
                        window.rememberMacOsLayoutOrigin()
                        window.bind(to: workspace.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                    case isMacosMinimized:
                        window.rememberMacOsLayoutOrigin(detachFromWorkspace: true)
                        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
                    case isMacosWindowOfHiddenApp:
                        window.rememberMacOsLayoutOrigin()
                        window.bind(to: workspace.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                    default: break
                }
            case .macos(let prevParentKind, let prevWorkspaceName):
                if !isMacosFullscreen && !isMacosMinimized && !isMacosWindowOfHiddenApp {
                    try await exitMacOsNativeUnconventionalState(
                        window: window,
                        prevParentKind: prevParentKind,
                        prevWorkspaceName: prevWorkspaceName,
                        workspace: workspace,
                    )
                }
        }
    }
}

@MainActor
func exitMacOsNativeUnconventionalState(
    window: Window,
    prevParentKind: NonLeafTreeNodeKind,
    prevWorkspaceName: String?,
    workspace fallbackWorkspace: Workspace,
) async throws {
    window.layoutReason = .standard
    let workspace = prevWorkspaceName
        .flatMap { Workspace.existing(byName: $0) }
        ?? fallbackWorkspace
    workspace.seedMonitorIfNeeded(fallbackWorkspace.workspaceMonitor)
    switch prevParentKind {
        case .workspace:
            window.bindAsFloatingWindow(to: workspace)
        case .tilingContainer:
            try await window.relayoutWindow(on: workspace, forceTile: true)
        case .macosPopupWindowsContainer: // Since the window was minimized/fullscreened it was mistakenly detected as popup. Relayout the window
            try await window.relayoutWindow(on: workspace)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer: // wtf case, should never be possible. But If encounter it, let's just re-layout window
            try await window.relayoutWindow(on: workspace)
    }
}
