@MainActor
func automaticWorkspaceDisplayIndex(_ workspace: Workspace, focusedWorkspace: Workspace?) -> Int? {
    monitorScopedAutomaticDisplayWorkspacesInExactProject(
        projectId: workspace.projectId,
        monitor: workspace.workspaceMonitor,
        focusedWorkspace: focusedWorkspace,
    )
        .firstIndex(of: workspace)
        .map { $0 + 1 }
}

func automaticWorkspaceDisplayIndexFallback(_ workspaceName: String) -> Int? {
    sidebarDraftWorkspaceIndex(workspaceName) ?? automaticWorkspaceIndex(workspaceName)
}

@MainActor
func scopedAutomaticDisplayWorkspaces(current: Workspace) -> [Workspace] {
    monitorScopedAutomaticDisplayWorkspaces(
        projectId: current.projectId,
        monitor: current.workspaceMonitor,
        focusedWorkspace: current,
    )
}

@MainActor
func monitorScopedAutomaticDisplayWorkspaces(
    projectId: WorkspaceProjectId,
    monitor: Monitor,
    focusedWorkspace: Workspace?,
) -> [Workspace] {
    orderedWorkspacesForPresentation()
        .filter { $0.projectId == projectId }
        .filter { $0.workspaceMonitor.rect.topLeftCorner == monitor.rect.topLeftCorner }
        .filter { userFacingWorkspaces([$0], focusedWorkspace: focusedWorkspace).contains($0) }
        .filter(\.usesAutomaticDisplayName)
}

@MainActor
func monitorScopedAutomaticDisplayWorkspacesInExactProject(
    projectId: WorkspaceProjectId,
    monitor: Monitor,
    focusedWorkspace: Workspace?,
) -> [Workspace] {
    orderedWorkspacesForPresentation()
        .filter { $0.projectId == projectId }
        .filter { $0.workspaceMonitor.rect.topLeftCorner == monitor.rect.topLeftCorner }
        .filter { userFacingWorkspaces([$0], focusedWorkspace: focusedWorkspace).contains($0) }
        .filter(\.usesAutomaticDisplayName)
}

@MainActor
func createAdjacentTransientBlankWorkspaceIfAllowed(named workspaceName: String, from current: Workspace) -> Workspace? {
    createAdjacentTransientBlankWorkspaceIfAllowed(
        named: workspaceName,
        projectId: current.projectId,
        monitor: current.workspaceMonitor,
        focusedWorkspace: current,
    )
}

@MainActor
func createAdjacentTransientBlankWorkspaceIfAllowed(
    named workspaceName: String,
    projectId: WorkspaceProjectId,
    monitor: Monitor,
    focusedWorkspace: Workspace?,
) -> Workspace? {
    guard let targetIndex = parsePositiveWorkspaceDisplayIndex(workspaceName) else {
        return nil
    }
    let automaticDisplayWorkspaces = monitorScopedAutomaticDisplayWorkspacesInExactProject(
        projectId: projectId,
        monitor: monitor,
        focusedWorkspace: focusedWorkspace,
    )
    guard targetIndex == automaticDisplayWorkspaces.count + 1 else { return nil }
    if let lastWorkspace = automaticDisplayWorkspaces.last,
       automaticDisplayWorkspaces.count > 1,
       lastWorkspace.isOrdinaryEmptySlot {
        return nil
    }

    let workspace = Workspace.get(byName: nextSidebarCreatedWorkspaceName(projectId: projectId, monitor: monitor))
    workspace.markAsTransientBlank()
    workspace.assignProject(projectId)
    workspace.seedMonitorIfNeeded(monitor)
    return workspace
}
