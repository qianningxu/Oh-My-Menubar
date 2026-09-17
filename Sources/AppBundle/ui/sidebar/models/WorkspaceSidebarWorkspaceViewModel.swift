struct WorkspaceSidebarWorkspaceViewModel: Hashable, Identifiable {
    let name: String
    let projectId: WorkspaceProjectId
    let folderId: WorkspaceFolderId
    let displayName: String
    let sidebarLabel: String
    let isGeneratedName: Bool
    let tabSummary: WorkspaceSidebarTabSummaryViewModel
    let monitorScopeId: String
    let monitorName: String?
    let isFocused: Bool
    let isVisible: Bool
    let items: [WorkspaceSidebarItemViewModel]

    var id: String { name }

    init(
        name: String,
        projectId: WorkspaceProjectId,
        folderId: WorkspaceFolderId? = nil,
        displayName: String,
        sidebarLabel: String,
        isGeneratedName: Bool,
        tabSummary: WorkspaceSidebarTabSummaryViewModel = .empty,
        monitorScopeId: String,
        monitorName: String?,
        isFocused: Bool,
        isVisible: Bool,
        items: [WorkspaceSidebarItemViewModel]
    ) {
        self.name = name
        self.projectId = projectId
        self.folderId = folderId ?? WorkspaceFolderId(projectId)
        self.displayName = displayName
        self.sidebarLabel = sidebarLabel
        self.isGeneratedName = isGeneratedName
        self.tabSummary = tabSummary
        self.monitorScopeId = monitorScopeId
        self.monitorName = monitorName
        self.isFocused = isFocused
        self.isVisible = isVisible
        self.items = items
    }
}

struct WorkspaceSidebarTabSummaryViewModel: Hashable {
    let title: String
    let subtitle: String?
    let appBundleId: String?
    let appBundlePath: String?
    let windowCount: Int
    let isEmpty: Bool

    static let empty = WorkspaceSidebarTabSummaryViewModel(
        title: "New tab",
        subtitle: nil,
        appBundleId: nil,
        appBundlePath: nil,
        windowCount: 0,
        isEmpty: true,
    )
}

struct WorkspaceSidebarMonitorScopeViewModel: Hashable, Identifiable {
    let id: String
    let displayName: String
    let subtitle: String?
    let systemImageName: String
    let isFocusedMonitor: Bool
}
