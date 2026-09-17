import CoreGraphics

struct WorkspaceSidebarSnapshot: Equatable {
    var workspaces: [WorkspaceSidebarWorkspaceViewModel]
    var projects: [WorkspaceSidebarProjectViewModel]
    var folders: [WorkspaceSidebarFolderViewModel] = []
    var activeProjectId: WorkspaceProjectId
    var monitorScopes: [WorkspaceSidebarMonitorScopeViewModel]
    var selectedMonitorScopeId: String
    var targetMonitorScopeId: String
    var focusedMonitorScopeId: String
    var visibleWidth: CGFloat
    var isAutoHideEnabled: Bool = false
    var isPinnedExpanded: Bool
    var hoveredWorkspaceName: String?
    var dropPreview: WorkspaceSidebarDropPreviewViewModel?
    var configuration: WorkspaceSidebarConfiguration

    static let empty = WorkspaceSidebarSnapshot(
        workspaces: [],
        projects: [],
        folders: [],
        activeProjectId: workspaceProjectDefaultId,
        monitorScopes: [],
        selectedMonitorScopeId: workspaceSidebarDefaultScopeId,
        targetMonitorScopeId: workspaceSidebarDefaultScopeId,
        focusedMonitorScopeId: "",
        visibleWidth: 0,
        isAutoHideEnabled: false,
        isPinnedExpanded: true,
        hoveredWorkspaceName: nil,
        dropPreview: nil,
        configuration: .empty,
    )
}

struct WorkspaceSidebarConfiguration: Equatable {
    var collapsedWidth: CGFloat
    var expandedWidth: CGFloat
    var topPadding: CGFloat
    var showMonitorSelector: Bool
    var showsDate: Bool
    var showsStatusPills: Bool
    var widgets: [WorkspaceSidebarWidgetConfig]

    static let empty = WorkspaceSidebarConfiguration(
        collapsedWidth: 0,
        expandedWidth: 0,
        topPadding: 0,
        showMonitorSelector: false,
        showsDate: false,
        showsStatusPills: false,
        widgets: [],
    )
}

enum WorkspaceSidebarAction: Equatable {
    case selectWorkspace(String)
    case overrideWorkspaceInUse(String)
    case selectWindow(UInt32)
    case closeWindow(UInt32)
    case selectProject(WorkspaceProjectId)
    case createProject(displayName: String? = nil)
    case createFolder
    case renameProject(WorkspaceProjectId, displayName: String)
    case setProjectColor(WorkspaceProjectId, colorHex: String?)
    case deleteProject(WorkspaceProjectId)
    case renameFolder(WorkspaceFolderId, displayName: String)
    case setFolderColor(WorkspaceFolderId, colorHex: String?)
    case deleteFolder(WorkspaceFolderId)
    case moveFolderToProject(WorkspaceFolderId, projectId: WorkspaceProjectId)
    case selectMonitorScope(String)
    case createWorkspace(projectId: WorkspaceProjectId, monitorScopeId: String)
    case renameWorkspace(String, displayName: String)
    case closeWorkspace(String)
    case reorderWorkspace(String, folderId: WorkspaceFolderId, placement: WorkspaceReorderPlacement)
    case moveWorkspaceToFolder(String, folderId: WorkspaceFolderId)
    case moveWorkspace(String, toWorkspace: String)
    case moveWorkspaceToProject(String, projectId: WorkspaceProjectId)
    case reorderFolder(WorkspaceFolderId, placement: WorkspaceSidebarFolderReorderPlacement)
    case setAutoHide(Bool)
    case setPinnedExpanded(Bool)
    case moveWindow(UInt32, toWorkspace: String)
    case moveTabGroup(UInt32, toWorkspace: String)
    case moveWindowToNewWorkspace(UInt32, projectId: WorkspaceProjectId, monitorScopeId: String)
    case moveTabGroupToNewWorkspace(UInt32, projectId: WorkspaceProjectId, monitorScopeId: String)
    case moveWindowToNewWorkspaceInFolder(UInt32, folderId: WorkspaceFolderId, monitorScopeId: String)
    case moveTabGroupToNewWorkspaceInFolder(UInt32, folderId: WorkspaceFolderId, monitorScopeId: String)
    case previewWindowDrop(UInt32, target: WorkspaceSidebarDropTargetKind)
    case previewTabGroupDrop(UInt32, target: WorkspaceSidebarDropTargetKind)
    case clearDropPreview
}

struct WorkspaceSidebarActions {
    var send: @MainActor (WorkspaceSidebarAction) -> Void
    var setDropTargets: @MainActor ([WorkspaceSidebarDropTargetFrame]) -> Void
    var hoverWorkspace: @MainActor (String, Bool) -> Void
    var windowDragChanged: @MainActor (UInt32, CGPoint) -> Void
    var windowDragEnded: @MainActor (UInt32, CGPoint) -> Void
    var tabGroupDragChanged: @MainActor (UInt32, CGPoint) -> Void
    var tabGroupDragEnded: @MainActor (UInt32, CGPoint) -> Void

    init(
        send: @escaping @MainActor (WorkspaceSidebarAction) -> Void = { _ in },
        setDropTargets: @escaping @MainActor ([WorkspaceSidebarDropTargetFrame]) -> Void = { _ in },
        hoverWorkspace: @escaping @MainActor (String, Bool) -> Void = { _, _ in },
        windowDragChanged: @escaping @MainActor (UInt32, CGPoint) -> Void = { _, _ in },
        windowDragEnded: @escaping @MainActor (UInt32, CGPoint) -> Void = { _, _ in },
        tabGroupDragChanged: @escaping @MainActor (UInt32, CGPoint) -> Void = { _, _ in },
        tabGroupDragEnded: @escaping @MainActor (UInt32, CGPoint) -> Void = { _, _ in }
    ) {
        self.send = send
        self.setDropTargets = setDropTargets
        self.hoverWorkspace = hoverWorkspace
        self.windowDragChanged = windowDragChanged
        self.windowDragEnded = windowDragEnded
        self.tabGroupDragChanged = tabGroupDragChanged
        self.tabGroupDragEnded = tabGroupDragEnded
    }
}
