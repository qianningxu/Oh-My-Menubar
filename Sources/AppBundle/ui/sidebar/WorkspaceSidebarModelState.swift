import AppKit

struct WorkspaceSidebarModelState {
    let workspaces: [WorkspaceSidebarWorkspaceViewModel]
    let projects: [WorkspaceSidebarProjectViewModel]
    let folders: [WorkspaceSidebarFolderViewModel]
    let activeProjectId: WorkspaceProjectId
    let monitorScopes: [WorkspaceSidebarMonitorScopeViewModel]
    let focusedMonitorScopeId: String
    let showsMonitorSelector: Bool
    let topPadding: CGFloat
    let hoveredWorkspaceName: String?
}
