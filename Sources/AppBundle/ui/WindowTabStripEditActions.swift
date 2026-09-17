import Common

@MainActor
func closeWindowFromTabStrip(_ windowId: UInt32, fallbackWorkspace: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            guard Window.get(byId: windowId) != nil else {
                _ = Workspace.existing(byName: fallbackWorkspace)?.focusWorkspace()
                await updateWindowTabModel()
                return
            }
            var args = CloseCmdArgs(rawArgs: [])
            args.windowId = windowId
            _ = try await CloseCommand(args: args).run(.defaultEnv, .emptyStdin)
            await updateWindowTabModel()
        }
    }
}

@MainActor
func removeWindowFromTabStrip(_ windowId: UInt32, fallbackWorkspace: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId) else {
                _ = Workspace.existing(byName: fallbackWorkspace)?.focusWorkspace()
                return
            }
            _ = removeWindowFromTabStack(window)
            window.nativeFocus()
        }
    }
}

@MainActor
func reorderTabInStrip(_ windowId: UInt32, toIndex targetIndex: Int) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId),
                  let parent = window.parent as? TilingContainer,
                  parent.layout == .tabGroup,
                  let currentIndex = window.ownIndex
            else { return }
            let clampedTarget = max(0, min(targetIndex, parent.children.count - 1))
            guard clampedTarget != currentIndex else { return }
            let binding = window.unbindFromParent()
            window.bind(to: parent, adaptiveWeight: binding.adaptiveWeight, index: clampedTarget)
            window.markAsMostRecentChild()
            _ = window.focusWindow()
        }
    }
}

@MainActor
func renameWindowTabFromTabStrip(_ windowId: UInt32, displayName: String, fallbackWorkspace: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            guard Window.get(byId: windowId) != nil else {
                _ = Workspace.existing(byName: fallbackWorkspace)?.focusWorkspace()
                await updateWindowTabModel()
                return
            }
            try await renameWindowTab(windowId: windowId, displayName: displayName)
            await updateWindowTabModel()
        }
    }
}

@MainActor
func moveWindowToProjectFromTabStrip(_ windowId: UInt32, projectId: WorkspaceProjectId) {
    guard let window = Window.get(byId: windowId),
          let workspace = window.nodeWorkspace
    else { return }
    let monitorScopeId = window.nodeMonitor.map(workspaceSidebarMonitorScopeId(for:))
        ?? workspaceSidebarMonitorScopeId(for: workspace.workspaceMonitor)
    moveWindowToNewWorkspaceFromSidebar(
        windowId,
        projectId: projectId,
        monitorScopeId: monitorScopeId,
    )
}
