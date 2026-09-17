import Foundation

@MainActor
func buildWorkspaceSidebarSnapshot() async -> WorkspaceSidebarSnapshot {
    guard TrayMenuModel.shared.isEnabled, config.workspaceSidebar.enabled else {
        return .empty
    }

    await refreshWorkspaceSidebarModelState()
    return WorkspaceSidebarSnapshot(
        workspaces: TrayMenuModel.shared.workspaceSidebarWorkspaces,
        projects: TrayMenuModel.shared.workspaceSidebarProjects,
        folders: TrayMenuModel.shared.workspaceSidebarFolders,
        activeProjectId: TrayMenuModel.shared.workspaceSidebarActiveProjectId,
        monitorScopes: TrayMenuModel.shared.workspaceSidebarMonitorScopes,
        selectedMonitorScopeId: TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId,
        targetMonitorScopeId: TrayMenuModel.shared.workspaceSidebarTargetMonitorScopeId,
        focusedMonitorScopeId: TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId,
        visibleWidth: TrayMenuModel.shared.workspaceSidebarVisibleWidth,
        isAutoHideEnabled: TrayMenuModel.shared.isWorkspaceSidebarAutoHideEnabled,
        isPinnedExpanded: TrayMenuModel.shared.isWorkspaceSidebarPinnedExpanded,
        hoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
        dropPreview: TrayMenuModel.shared.workspaceSidebarDropPreview,
        configuration: workspaceSidebarConfiguration(),
    )
}

@MainActor
func refreshWorkspaceSidebarModelState() async {
    await updateWorkspaceSidebarModel()
}

@MainActor
func applyWorkspaceSidebarSnapshotToTrayModel(_ snapshot: WorkspaceSidebarSnapshot) {
    TrayMenuModel.shared.workspaceSidebarWorkspaces = snapshot.workspaces
    TrayMenuModel.shared.workspaceSidebarProjects = snapshot.projects
    TrayMenuModel.shared.workspaceSidebarFolders = snapshot.folders
    TrayMenuModel.shared.workspaceSidebarActiveProjectId = snapshot.activeProjectId
    TrayMenuModel.shared.workspaceSidebarMonitorScopes = snapshot.monitorScopes
    TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId = snapshot.selectedMonitorScopeId
    TrayMenuModel.shared.workspaceSidebarTargetMonitorScopeId = snapshot.targetMonitorScopeId
    TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId = snapshot.focusedMonitorScopeId
    TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector = snapshot.configuration.showMonitorSelector
    TrayMenuModel.shared.workspaceSidebarVisibleWidth = snapshot.visibleWidth
    TrayMenuModel.shared.isWorkspaceSidebarAutoHideEnabled = snapshot.isAutoHideEnabled
    TrayMenuModel.shared.isWorkspaceSidebarPinnedExpanded = snapshot.isPinnedExpanded
    TrayMenuModel.shared.workspaceSidebarTopPadding = snapshot.configuration.topPadding
    TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = snapshot.hoveredWorkspaceName
    TrayMenuModel.shared.workspaceSidebarDropPreview = snapshot.dropPreview
}

@MainActor
func workspaceSidebarConfiguration() -> WorkspaceSidebarConfiguration {
    WorkspaceSidebarConfiguration(
        collapsedWidth: workspaceSidebarCompactContentWidth,
        expandedWidth: CGFloat(config.workspaceSidebar.width),
        topPadding: TrayMenuModel.shared.workspaceSidebarTopPadding,
        showMonitorSelector: TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector,
        showsDate: config.workspaceSidebar.showDate,
        showsStatusPills: config.workspaceSidebar.showStatusPills,
        widgets: config.workspaceSidebar.resolvedWidgets,
    )
}
