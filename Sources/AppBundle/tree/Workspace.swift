import Foundation

let sidebarDraftWorkspacePrefix = "__sidebar_draft_workspace_"
let internalAutomaticWorkspacePrefix = "__internal_auto_workspace_"
let workspaceProjectDefaultId = WorkspaceProjectId.defaultProject
let workspaceDefaultFolderDisplayName = "Unfolded"
let workspaceFolderDefaultId = WorkspaceFolderId(workspaceProjectDefaultId)

func workspaceProjectUnfoldedFolderId(_ projectId: WorkspaceProjectId) -> WorkspaceFolderId {
    projectId == workspaceProjectDefaultId
        ? workspaceFolderDefaultId
        : WorkspaceFolderId("unfolded-\(projectId.rawValue)")
}

struct WorkspaceProject: Hashable, Identifiable {
    let id: WorkspaceProjectId
    var name: String
    let order: Int
    var unfoldedFolderId: WorkspaceFolderId
    var folderOrder: [WorkspaceFolderId] = []
    var linkedViewportIds: Set<MonitorViewportId> = []

    init(
        id: WorkspaceProjectId,
        name: String,
        order: Int,
        unfoldedFolderId: WorkspaceFolderId? = nil,
        folderOrder: [WorkspaceFolderId] = [],
        linkedViewportIds: Set<MonitorViewportId> = []
    ) {
        self.id = id
        self.name = name
        self.order = order
        let unfoldedFolderId = unfoldedFolderId ?? workspaceProjectUnfoldedFolderId(id)
        self.unfoldedFolderId = unfoldedFolderId
        self.folderOrder = folderOrder.isEmpty ? [unfoldedFolderId] : folderOrder
        self.linkedViewportIds = linkedViewportIds
    }
}

struct WorkspaceFolderId: RawRepresentable, Hashable, Identifiable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible, Comparable {
    let rawValue: String

    var id: Self { self }
    var backingProjectId: WorkspaceProjectId { WorkspaceProjectId(rawValue) }
    var description: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    init(_ backingProjectId: WorkspaceProjectId) {
        self.init(rawValue: backingProjectId.rawValue)
    }

    init(stringLiteral value: String) {
        self.init(value)
    }

    static func < (lhs: WorkspaceFolderId, rhs: WorkspaceFolderId) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct WorkspaceFolder: Hashable, Identifiable {
    let id: WorkspaceFolderId
    var projectId: WorkspaceProjectId
    var name: String
    var order: Int
    var workspaceOrder: [WorkspaceId] = []
    var linkedViewportIds: Set<MonitorViewportId> = []

    init(
        id: WorkspaceFolderId,
        projectId: WorkspaceProjectId = workspaceProjectDefaultId,
        name: String,
        order: Int,
        workspaceOrder: [WorkspaceId] = [],
        linkedViewportIds: Set<MonitorViewportId> = []
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.order = order
        self.workspaceOrder = workspaceOrder
        self.linkedViewportIds = linkedViewportIds
    }

}

enum WorkspaceMutationError: LocalizedError {
    case workspaceNotFound(String)
    case workspaceCannotBeDeleted(String)
    case projectNotFound(String)
    case projectCannotBeDeleted(String)
    case workspaceCloseBlocked(String, Int)
    case projectCloseBlocked(String, Int)
    case emptyName
    case duplicateProjectName(String)

    var errorDescription: String? {
        switch self {
            case .workspaceNotFound(let name):
                "Tab '\(name)' no longer exists."
            case .workspaceCannotBeDeleted(let name):
                "Tab '\(name)' cannot be deleted."
            case .projectNotFound(let id):
                "Project '\(id)' no longer exists."
            case .projectCannotBeDeleted(let name):
                "Project '\(name)' cannot be deleted."
            case .workspaceCloseBlocked(let name, let count):
                "Tab '\(name)' was not closed because \(count) window\(count == 1 ? "" : "s") stayed open."
            case .projectCloseBlocked(let name, let count):
                "Project '\(name)' was not deleted because \(count) window\(count == 1 ? "" : "s") stayed open."
            case .emptyName:
                "Name cannot be empty."
            case .duplicateProjectName(let name):
                "A project named '\(name)' already exists."
        }
    }
}

enum WorkspaceNamingStyle: String, Codable, Sendable {
    case explicit
    case automatic
}

enum WorkspaceReorderPlacement: Equatable {
    case before(String)
    case after(String)

    var targetWorkspaceName: String {
        switch self {
            case .before(let name), .after(let name): name
        }
    }
}

enum WorkspaceOrderDestination: Equatable {
    case before(WorkspaceId)
    case after(WorkspaceId)

    var targetWorkspaceId: WorkspaceId {
        switch self {
            case .before(let id), .after(let id): id
        }
    }
}
