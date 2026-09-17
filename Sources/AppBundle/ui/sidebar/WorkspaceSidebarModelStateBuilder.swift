import AppKit

@MainActor
func buildWorkspaceSidebarModelState() async -> WorkspaceSidebarModelState {
    let hierarchy = prepareWorkspaceSidebarHierarchyInputs()
    let currentFocus = focus
    let availableMonitors = sortedMonitors
    let focusedMonitorScopeId = workspaceSidebarMonitorScopeId(for: currentFocus.workspace.workspaceMonitor)
    let monitorScopes = buildWorkspaceSidebarMonitorScopes(
        sortedMonitors: availableMonitors,
        focusedMonitorScopeId: focusedMonitorScopeId,
    )
    let activeProjectId = currentFocus.workspace.projectId
    let projects = buildWorkspaceSidebarProjectViewModels(from: hierarchy.projects)
    let folders = buildWorkspaceSidebarFolderViewModels(from: hierarchy.folders)
    let workspaces = await buildWorkspaceSidebarWorkspaceViewModels(
        from: hierarchy.orderedWorkspaces,
        currentFocus: currentFocus,
        workspaceLabels: config.workspaceSidebar.workspaceLabels,
        availableMonitors: availableMonitors,
    )
    return WorkspaceSidebarModelState(
        workspaces: workspaces,
        projects: projects,
        folders: folders,
        activeProjectId: activeProjectId,
        monitorScopes: monitorScopes,
        focusedMonitorScopeId: focusedMonitorScopeId,
        showsMonitorSelector: availableMonitors.count > 1,
        topPadding: 0,
        hoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
    )
}
