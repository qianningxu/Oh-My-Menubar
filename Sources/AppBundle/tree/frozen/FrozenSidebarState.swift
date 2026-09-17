import Foundation

struct FrozenSidebarState: Codable, Sendable {
    let projects: [FrozenSidebarProject]
    let collapsedFolderIds: [WorkspaceFolderId]
    let workspaceLabels: [String: String]
    let projectLabels: [String: String]
    let projectColors: [String: String]
    let folderLabels: [String: String]
    let folderColors: [String: String]

    @MainActor
    init(restorableWorkspaces: [Workspace]) {
        let restorableWorkspaceIds = Set(restorableWorkspaces.map(\.id))
        let restorableWorkspaceNames = Set(restorableWorkspaces.map(\.name))
        winMuxWorkspaceState.pruneProjectWorkspaceIndexes()
        projects = workspaceProjects().map { project in
            FrozenSidebarProject(
                project: project,
                folders: workspaceFoldersInSidebarOrder(projectId: project.id),
                restorableWorkspaces: restorableWorkspaces,
                restorableWorkspaceIds: restorableWorkspaceIds
            )
        }

        let knownFolderIds = Set(winMuxWorkspaceState.workspaceFoldersById.keys.map(\.rawValue))
        var persistedCollapsedFolderIds: [WorkspaceFolderId] = []
        for rawFolderId in collapsedWorkspaceSidebarFolderIdsPreference()
        where knownFolderIds.contains(rawFolderId) {
            persistedCollapsedFolderIds.append(WorkspaceFolderId(rawFolderId))
        }
        collapsedFolderIds = persistedCollapsedFolderIds.sorted()
        workspaceLabels = Dictionary(uniqueKeysWithValues: config.workspaceSidebar.workspaceLabels.filter {
            restorableWorkspaceNames.contains($0.key)
        })
        let knownProjectIds = Set(projects.map { $0.id.rawValue })
        projectLabels = Dictionary(uniqueKeysWithValues: config.workspaceSidebar.projectLabels.filter {
            knownProjectIds.contains($0.key)
        })
        projectColors = Dictionary(uniqueKeysWithValues: config.workspaceSidebar.projectColors.filter {
            knownProjectIds.contains($0.key)
        })
        folderLabels = Dictionary(uniqueKeysWithValues: config.workspaceSidebar.folderLabels.filter {
            knownFolderIds.contains($0.key)
        })
        folderColors = Dictionary(uniqueKeysWithValues: config.workspaceSidebar.folderColors.filter {
            knownFolderIds.contains($0.key)
        })
    }

    private enum CodingKeys: String, CodingKey {
        case projects
        case collapsedFolderIds
        case workspaceLabels
        case projectLabels
        case projectColors
        case folderLabels
        case folderColors
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedProjects = try container.decode([FrozenSidebarProject].self, forKey: .projects)
        let legacyFolders = decodedProjects.compactMap(\.legacyFolder)
        let isLegacy = !decodedProjects.isEmpty && legacyFolders.count == decodedProjects.count
        if isLegacy {
            projects = [FrozenSidebarProject(
                id: workspaceProjectDefaultId,
                name: "Main",
                order: 0,
                unfoldedFolderId: workspaceFolderDefaultId,
                folders: legacyFolders
            )]
        } else {
            projects = decodedProjects
        }
        collapsedFolderIds = try container.decodeIfPresent([WorkspaceFolderId].self, forKey: .collapsedFolderIds) ?? []
        workspaceLabels = try container.decodeIfPresent([String: String].self, forKey: .workspaceLabels) ?? [:]
        let decodedProjectLabels = try container.decodeIfPresent([String: String].self, forKey: .projectLabels) ?? [:]
        let decodedProjectColors = try container.decodeIfPresent([String: String].self, forKey: .projectColors) ?? [:]
        projectLabels = isLegacy ? [workspaceProjectDefaultId.rawValue: "Main"] : decodedProjectLabels
        projectColors = isLegacy ? [:] : decodedProjectColors
        let decodedFolderLabels = try container.decodeIfPresent([String: String].self, forKey: .folderLabels) ?? [:]
        folderLabels = isLegacy ? decodedProjectLabels.merging(decodedFolderLabels) { _, current in current } : decodedFolderLabels
        let decodedFolderColors = try container.decodeIfPresent([String: String].self, forKey: .folderColors) ?? [:]
        folderColors = isLegacy ? decodedProjectColors.merging(decodedFolderColors) { _, current in current } : decodedFolderColors
    }
}

struct FrozenSidebarProject: Codable, Sendable {
    let id: WorkspaceProjectId
    let name: String
    let order: Int
    let unfoldedFolderId: WorkspaceFolderId
    let folders: [FrozenSidebarFolder]
    fileprivate let legacyFolder: FrozenSidebarFolder?

    var workspaceNames: [String] { folders.flatMap(\.workspaceNames) }

    init(
        id: WorkspaceProjectId,
        name: String,
        order: Int,
        unfoldedFolderId: WorkspaceFolderId,
        folders: [FrozenSidebarFolder]
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.unfoldedFolderId = unfoldedFolderId
        self.folders = folders
        legacyFolder = nil
    }

    @MainActor
    init(
        project: WorkspaceProject,
        folders: [WorkspaceFolder],
        restorableWorkspaces: [Workspace],
        restorableWorkspaceIds: Set<WorkspaceId>
    ) {
        id = project.id
        name = project.name
        order = project.order
        unfoldedFolderId = project.unfoldedFolderId
        self.folders = folders.map {
            FrozenSidebarFolder(
                folder: $0,
                restorableWorkspaces: restorableWorkspaces,
                restorableWorkspaceIds: restorableWorkspaceIds
            )
        }
        legacyFolder = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case order
        case unfoldedFolderId
        case folders
        case workspaceNames
        case linkedViewportIds
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.folders) {
            id = try container.decode(WorkspaceProjectId.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            order = try container.decode(Int.self, forKey: .order)
            unfoldedFolderId = try container.decodeIfPresent(WorkspaceFolderId.self, forKey: .unfoldedFolderId)
                ?? workspaceProjectUnfoldedFolderId(id)
            folders = try container.decode([FrozenSidebarFolder].self, forKey: .folders)
            legacyFolder = nil
        } else {
            let legacyId = try container.decode(WorkspaceProjectId.self, forKey: .id)
            let folder = FrozenSidebarFolder(
                id: WorkspaceFolderId(legacyId.rawValue),
                name: try container.decode(String.self, forKey: .name),
                order: try container.decode(Int.self, forKey: .order),
                workspaceNames: try container.decodeIfPresent([String].self, forKey: .workspaceNames) ?? [],
                linkedViewportIds: try container.decodeIfPresent(Set<MonitorViewportId>.self, forKey: .linkedViewportIds) ?? []
            )
            id = legacyId
            name = folder.name
            order = folder.order
            unfoldedFolderId = workspaceFolderDefaultId
            folders = []
            legacyFolder = folder
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(order, forKey: .order)
        try container.encode(unfoldedFolderId, forKey: .unfoldedFolderId)
        try container.encode(folders, forKey: .folders)
    }
}

struct FrozenSidebarFolder: Codable, Sendable {
    let id: WorkspaceFolderId
    let name: String
    let order: Int
    let workspaceNames: [String]
    let linkedViewportIds: Set<MonitorViewportId>

    init(
        id: WorkspaceFolderId,
        name: String,
        order: Int,
        workspaceNames: [String],
        linkedViewportIds: Set<MonitorViewportId>
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.workspaceNames = workspaceNames
        self.linkedViewportIds = linkedViewportIds
    }

    @MainActor
    init(
        folder: WorkspaceFolder,
        restorableWorkspaces: [Workspace],
        restorableWorkspaceIds: Set<WorkspaceId>
    ) {
        id = folder.id
        name = folder.name
        order = folder.order
        linkedViewportIds = folder.linkedViewportIds
        var seen: Set<WorkspaceId> = []
        var names = folder.workspaceOrder.compactMap { workspaceId -> String? in
            guard restorableWorkspaceIds.contains(workspaceId),
                  seen.insert(workspaceId).inserted
            else { return nil }
            return winMuxWorkspaceState.workspaceById[workspaceId]?.name
        }
        names.append(contentsOf: restorableWorkspaces.compactMap { workspace in
            guard workspace.folderId == folder.id,
                  seen.insert(workspace.id).inserted
            else { return nil }
            return workspace.name
        })
        workspaceNames = names
    }
}

@MainActor
func restoreFrozenSidebarState(
    _ sidebar: FrozenSidebarState?,
    restoredWorkspaceNames: Set<String>,
    materializeMissingWorkspaces: Bool = false
) {
    guard let sidebar else { return }
    let persistedWorkspaceNames = sidebar.projects.flatMap { $0.folders.flatMap(\.workspaceNames) }
    let effectiveRestoredWorkspaceNames = materializeMissingWorkspaces
        ? restoredWorkspaceNames.union(persistedWorkspaceNames)
        : restoredWorkspaceNames

    for frozenProject in sidebar.projects.sorted(by: { $0.order < $1.order }) {
        winMuxWorkspaceState.registerProject(WorkspaceProject(
            id: frozenProject.id,
            name: frozenProject.name,
            order: frozenProject.order,
            unfoldedFolderId: frozenProject.unfoldedFolderId,
            folderOrder: frozenProject.folders.map(\.id)
        ))
        for frozenFolder in frozenProject.folders.sorted(by: { $0.order < $1.order }) {
            let restoredWorkspaces = frozenFolder.workspaceNames.compactMap { workspaceName -> Workspace? in
                if let workspace = Workspace.existing(byName: workspaceName),
                   effectiveRestoredWorkspaceNames.contains(workspaceName)
                {
                    return workspace
                }
                return materializeMissingWorkspaces ? Workspace.get(byName: workspaceName) : nil
            }
            winMuxWorkspaceState.registerFolder(WorkspaceFolder(
                id: frozenFolder.id,
                projectId: frozenProject.id,
                name: frozenFolder.name,
                order: frozenFolder.order,
                workspaceOrder: restoredWorkspaces.map(\.id),
                linkedViewportIds: frozenFolder.linkedViewportIds
            ))
            for workspace in restoredWorkspaces where workspace.folderId != frozenFolder.id {
                workspace.assignFolder(frozenFolder.id)
            }
        }
        winMuxWorkspaceState.ensureUnfoldedFolderExists(for: frozenProject.id)
    }

    restoreFrozenSidebarMetadata(sidebar, restoredWorkspaceNames: effectiveRestoredWorkspaceNames)
    restoreWorkspaceSidebarCollapsedFolderIds(sidebar.collapsedFolderIds)
    winMuxWorkspaceState.pruneProjectWorkspaceIndexes()
}

@MainActor
private func restoreFrozenSidebarMetadata(_ sidebar: FrozenSidebarState, restoredWorkspaceNames: Set<String>) {
    mergeMissingSidebarMetadata(sidebar.workspaceLabels, into: &config.workspaceSidebar.workspaceLabels) {
        restoredWorkspaceNames.contains($0)
    }
    mergeMissingSidebarMetadata(sidebar.projectLabels, into: &config.workspaceSidebar.projectLabels) {
        winMuxWorkspaceState.projectsById[WorkspaceProjectId($0)] != nil
    }
    mergeMissingSidebarMetadata(sidebar.projectColors, into: &config.workspaceSidebar.projectColors) {
        winMuxWorkspaceState.projectsById[WorkspaceProjectId($0)] != nil
    }
    mergeMissingSidebarMetadata(sidebar.folderLabels, into: &config.workspaceSidebar.folderLabels) {
        winMuxWorkspaceState.workspaceFoldersById[WorkspaceFolderId($0)] != nil
    }
    mergeMissingSidebarMetadata(sidebar.folderColors, into: &config.workspaceSidebar.folderColors) {
        winMuxWorkspaceState.workspaceFoldersById[WorkspaceFolderId($0)] != nil
    }
}

private func mergeMissingSidebarMetadata(
    _ restored: [String: String],
    into current: inout [String: String],
    where shouldRestore: (String) -> Bool
) {
    for (key, value) in restored where shouldRestore(key) {
        let currentValue = current[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentValue?.isEmpty ?? true {
            current[key] = value
        }
    }
}
