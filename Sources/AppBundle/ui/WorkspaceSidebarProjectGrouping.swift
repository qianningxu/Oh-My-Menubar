import Foundation

func workspaceSidebarVisibleWorkspacesByProject(
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
    selectedScopeId: String,
    focusedMonitorScopeId: String,
    targetMonitorScopeId: String? = nil,
    browsedProjectId: WorkspaceProjectId? = nil,
    projectsEnabled: Bool = true,
) -> [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]] {
    if !projectsEnabled {
        let resolvedScopeId = workspaceSidebarTabListScopeId(
            selectedScopeId: selectedScopeId,
            targetMonitorScopeId: targetMonitorScopeId,
        )
        return [workspaceProjectDefaultId: workspaces.filter {
            workspaceSidebarWorkspaceMatchesScope(
                $0,
                selectedScopeId: resolvedScopeId,
                focusedMonitorScopeId: focusedMonitorScopeId,
            )
        }]
    }
    var result: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]] = [:]
    for workspace in workspaces {
        if workspace.projectId != browsedProjectId &&
            !workspaceSidebarWorkspaceMatchesScope(
                workspace,
                selectedScopeId: selectedScopeId,
                focusedMonitorScopeId: focusedMonitorScopeId,
            )
        {
            continue
        }
        result[workspace.projectId, default: []].append(workspace)
    }
    return result
}

func workspaceSidebarWorkspaceIsInUseOnOtherDisplay(
    _ workspace: WorkspaceSidebarWorkspaceViewModel,
    selectedScopeId: String,
) -> Bool {
    guard selectedScopeId != workspaceSidebarDefaultScopeId,
          selectedScopeId != workspaceSidebarFocusedScopeId,
          workspace.isVisible
    else {
        return false
    }
    return workspace.monitorScopeId != selectedScopeId
}
