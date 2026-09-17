import Common

@MainActor
func resetWorkspaceNameGenerationStateForTests() {
    for workspace in Workspace.all {
        workspace.setFolderIdFromWorkspaceState(workspaceFolderDefaultId)
    }
    winMuxWorkspaceState.resetProjects(defaultProjectName: workspaceProjectDisplayName(workspaceProjectDefaultId, fallbackName: workspaceDefaultFolderDisplayName))
}

@MainActor
func resetWinMuxWorkspaceStateForTests() {
    for window in globalFloatingWindowsContainer.children { window.unbindFromParent() }
    for workspace in Workspace.all {
        workspace.lifecycle = .durable
    }
    winMuxWorkspaceState.resetWorkspaceRegistryForTests(
        defaultProjectName: workspaceProjectDisplayName(workspaceProjectDefaultId, fallbackName: workspaceDefaultFolderDisplayName),
    )
}

@MainActor
func activateMonitorViewportFallbackWorkspaceForTests(on monitor: Monitor) -> Workspace {
    let workspace = getOrCreateMonitorViewportFallbackWorkspace(for: monitor)
    check(monitor.setActiveWorkspace(workspace))
    return workspace
}
