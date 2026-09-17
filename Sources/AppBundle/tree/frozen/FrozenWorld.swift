struct FrozenWorld: Codable, Sendable {
    let workspaces: [FrozenWorkspace]
    let monitors: [FrozenMonitor]
    let windowIds: Set<UInt32>
    let sidebar: FrozenSidebarState?
    let globalFloatingWindows: [FrozenWindow]?

    init(
        workspaces: [FrozenWorkspace],
        monitors: [FrozenMonitor],
        windowIds: Set<UInt32>,
        sidebar: FrozenSidebarState? = nil,
        globalFloatingWindows: [FrozenWindow]? = nil
    ) {
        self.workspaces = workspaces
        self.monitors = monitors
        self.windowIds = windowIds
        self.sidebar = sidebar
        self.globalFloatingWindows = globalFloatingWindows
    }
}

@MainActor
func snapshotCurrentFrozenWorld() -> FrozenWorld {
    let workspaces = restorableWorkspaces(orderedWorkspacesForPresentation())
    return FrozenWorld(
        workspaces: workspaces.map(FrozenWorkspace.init),
        monitors: monitors.map(FrozenMonitor.init),
        windowIds: (workspaces.flatMap { collectAllWindowIds(workspace: $0) } + globalFloatingWindowsContainer.allLeafWindowsRecursive.map(\.windowId)).toSet(),
        sidebar: FrozenSidebarState(restorableWorkspaces: workspaces),
        globalFloatingWindows: globalFloatingWindowsContainer.allLeafWindowsRecursive.map(FrozenWindow.init),
    )
}

@MainActor
func restorableWorkspaces(_ workspaces: [Workspace]) -> [Workspace] {
    workspaces.filter { !collectAllWindowIds(workspace: $0).isEmpty }
}

@MainActor
func collectAllWindowIds(workspace: Workspace) -> [UInt32] {
    workspace.floatingWindows.map { $0.windowId } +
        workspaceOwnedMinimizedWindows(workspace).map { $0.windowId } +
        (workspace.existingMacOsNativeFullscreenWindowsContainer?.children.filterIsInstance(of: Window.self).map { $0.windowId } ?? []) +
        (workspace.existingMacOsNativeHiddenAppsWindowsContainer?.children.filterIsInstance(of: Window.self).map { $0.windowId } ?? []) +
        collectAllWindowIdsRecursive(workspace.rootTilingContainer)
}

func collectAllWindowIdsRecursive(_ node: TreeNode) -> [UInt32] {
    switch node.nodeCases {
        case .macosFullscreenWindowsContainer,
             .macosHiddenAppsWindowsContainer,
             .macosMinimizedWindowsContainer,
             .macosPopupWindowsContainer,
             .workspace: []
        case .tilingContainer(let c):
            c.children.reduce(into: [UInt32]()) { partialResult, elem in
                partialResult += collectAllWindowIdsRecursive(elem)
            }
        case .window(let w): [w.windowId]
    }
}
