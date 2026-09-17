import AppKit

enum WorkspaceSidebarPanelModelUpdate: Equatable {
    case refreshAll
    case syncVisibleModels
}

func workspaceSidebarPanelModelUpdate(
    didGeometryChange: Bool,
    didMonitorConfigurationChange: Bool,
    hasVisiblePanels: Bool,
) -> WorkspaceSidebarPanelModelUpdate {
    didGeometryChange || didMonitorConfigurationChange || !hasVisiblePanels
        ? .refreshAll
        : .syncVisibleModels
}

@MainActor
func clearWorkspaceSidebarModelState() {
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarWorkspaces, to: [])
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarMonitorScopes, to: [])
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarProjects, to: [])
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarFolders, to: [])
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarShowsMonitorSelector, to: false)
    WorkspaceSidebarPanel.refreshAll()
}

@MainActor
func applyWorkspaceSidebarModelState(_ state: WorkspaceSidebarModelState, previousTopPadding: CGFloat) {
    let didMonitorConfigurationChange =
        TrayMenuModel.shared.workspaceSidebarMonitorScopes != state.monitorScopes ||
        TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector != state.showsMonitorSelector

    updateWorkspaceSidebarTrayModel(with: state)
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarWorkspaces, to: state.workspaces)

    switch workspaceSidebarPanelModelUpdate(
        didGeometryChange: state.topPadding != previousTopPadding,
        didMonitorConfigurationChange: didMonitorConfigurationChange,
        hasVisiblePanels: !WorkspaceSidebarPanel.visiblePanels.isEmpty,
    ) {
        case .refreshAll:
            WorkspaceSidebarPanel.refreshAll()
        case .syncVisibleModels:
            WorkspaceSidebarPanel.syncVisiblePanelModelsFromShared()
    }
}

@MainActor
private func updateWorkspaceSidebarTrayModel(with state: WorkspaceSidebarModelState) {
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarTopPadding, to: state.topPadding)
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarHoveredWorkspaceName, to: state.hoveredWorkspaceName)
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarProjects, to: state.projects)
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarFolders, to: state.folders)
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarActiveProjectId, to: state.activeProjectId)
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarMonitorScopes, to: state.monitorScopes)
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarFocusedMonitorScopeId, to: state.focusedMonitorScopeId)
    TrayMenuModel.shared.setIfChanged(\.workspaceSidebarShowsMonitorSelector, to: state.showsMonitorSelector)
}
