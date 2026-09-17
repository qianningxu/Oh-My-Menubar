import AppKit

@MainActor
struct MonitorViewport {
    let id: MonitorViewportId
    var activeWorkspaceId: WorkspaceId?
    var previousWorkspaceId: WorkspaceId?
    var lastActiveWorkspaceByProject: [WorkspaceProjectId: WorkspaceId] = [:]
}

@MainActor
struct WinMuxWorkspaceState {
    var workspaceById: [WorkspaceId: Workspace] = [:]
    var workspaceIdByName: [String: WorkspaceId] = [:]
    var projectsById: [WorkspaceProjectId: WorkspaceProject] = [
        workspaceProjectDefaultId: WorkspaceProject(
            id: workspaceProjectDefaultId,
            name: "Main",
            order: 0,
        ),
    ] {
        didSet {
            guard oldValue != projectsById else { return }
            scheduleSidebarStatePersistenceForRestart()
        }
    }
    var workspaceFoldersById: [WorkspaceFolderId: WorkspaceFolder] = [
        workspaceFolderDefaultId: WorkspaceFolder(
            id: workspaceFolderDefaultId,
            projectId: workspaceProjectDefaultId,
            name: workspaceDefaultFolderDisplayName,
            order: 0,
        ),
    ] {
        didSet {
            guard oldValue != workspaceFoldersById else { return }
            scheduleSidebarStatePersistenceForRestart()
        }
    }
    var monitorViewportsById: [MonitorViewportId: MonitorViewport] = [:]

    private var nextWorkspaceCounter = 1
    private var nextProjectCounter = 1
    private var nextProjectOrderCounter = 1
    private var nextFolderCounter = 1
    private var nextFolderOrderCounter = 1

    mutating func resetProjects(defaultProjectName: String) {
        projectsById = [
            workspaceProjectDefaultId: WorkspaceProject(
                id: workspaceProjectDefaultId,
                name: defaultProjectName,
                order: 0,
            ),
        ]
        workspaceFoldersById = [
            workspaceFolderDefaultId: WorkspaceFolder(
                id: workspaceFolderDefaultId,
                projectId: workspaceProjectDefaultId,
                name: workspaceDefaultFolderDisplayName,
                order: 0,
            ),
        ]
        nextProjectCounter = 1
        nextProjectOrderCounter = 1
        nextFolderCounter = 1
        nextFolderOrderCounter = 1
        for workspace in workspaceById.values {
            workspace.setFolderIdFromWorkspaceState(workspaceFolderDefaultId)
        }
        rebuildFolderWorkspaceIndexes()
    }

    mutating func resetDisplayAssignments() {
        monitorViewportsById = [:]
    }

    mutating func resetWorkspaceRegistryForTests(defaultProjectName: String) {
        workspaceById = [:]
        workspaceIdByName = [:]
        monitorViewportsById = [:]
        projectsById = [
            workspaceProjectDefaultId: WorkspaceProject(
                id: workspaceProjectDefaultId,
                name: defaultProjectName,
                order: 0,
            ),
        ]
        workspaceFoldersById = [
            workspaceFolderDefaultId: WorkspaceFolder(
                id: workspaceFolderDefaultId,
                projectId: workspaceProjectDefaultId,
                name: workspaceDefaultFolderDisplayName,
                order: 0,
            ),
        ]
        nextWorkspaceCounter = 1
        nextProjectCounter = 1
        nextProjectOrderCounter = 1
        nextFolderCounter = 1
        nextFolderOrderCounter = 1
    }

    mutating func nextWorkspaceId() -> WorkspaceId {
        while workspaceById[WorkspaceId("workspace-\(nextWorkspaceCounter)")] != nil {
            nextWorkspaceCounter += 1
        }
        defer { nextWorkspaceCounter += 1 }
        return WorkspaceId("workspace-\(nextWorkspaceCounter)")
    }

    mutating func nextProjectOrder() -> Int {
        while projectsById.values.contains(where: { $0.order == nextProjectOrderCounter }) {
            nextProjectOrderCounter += 1
        }
        defer { nextProjectOrderCounter += 1 }
        return nextProjectOrderCounter
    }

    mutating func registerProject(_ project: WorkspaceProject) {
        projectsById[project.id] = project
        nextProjectOrderCounter = max(nextProjectOrderCounter, project.order + 1)
    }

    mutating func nextFolderOrder() -> Int {
        while workspaceFoldersById.values.contains(where: { $0.order == nextFolderOrderCounter }) {
            nextFolderOrderCounter += 1
        }
        defer { nextFolderOrderCounter += 1 }
        return nextFolderOrderCounter
    }

    mutating func registerFolder(_ folder: WorkspaceFolder) {
        workspaceFoldersById[folder.id] = folder
        nextFolderOrderCounter = max(nextFolderOrderCounter, folder.order + 1)
        ensureProjectExists(folder.projectId)
        insertFolder(folder.id, intoProject: folder.projectId)
    }

    mutating func nextGeneratedProjectIdentity() -> (id: WorkspaceProjectId, name: String) {
        while projectsById[WorkspaceProjectId("workspace-project-\(nextProjectCounter)")] != nil {
            nextProjectCounter += 1
        }
        defer { nextProjectCounter += 1 }
        return (WorkspaceProjectId("workspace-project-\(nextProjectCounter)"), "Project \(nextProjectCounter)")
    }

    mutating func nextGeneratedFolderIdentity() -> (id: WorkspaceFolderId, name: String) {
        while workspaceFoldersById[WorkspaceFolderId("project-\(nextFolderCounter)")] != nil {
            nextFolderCounter += 1
        }
        defer { nextFolderCounter += 1 }
        return (WorkspaceFolderId("project-\(nextFolderCounter)"), "Folder \(nextFolderCounter)")
    }

    func workspace(named name: String) -> Workspace? {
        workspaceIdByName[name].flatMap { workspaceById[$0] }
    }

    mutating func registerWorkspace(_ workspace: Workspace) {
        workspaceById[workspace.id] = workspace
        workspaceIdByName[workspace.name] = workspace.id
        ensureFolderExists(workspace.folderId)
        insertWorkspace(workspace.id, intoFolder: workspace.folderId)
    }

    mutating func removeWorkspace(_ workspace: Workspace) -> MonitorViewportId? {
        workspaceById.removeValue(forKey: workspace.id)
        workspaceIdByName.removeValue(forKey: workspace.name)
        removeWorkspaceFromFolderIndexes(workspace.id)

        var removedViewport: MonitorViewportId?
        for (viewportId, viewport) in monitorViewportsById {
            var viewport = viewport
            if viewport.activeWorkspaceId == workspace.id {
                viewport.activeWorkspaceId = nil
                removedViewport = viewportId
            }
            if viewport.previousWorkspaceId == workspace.id {
                viewport.previousWorkspaceId = nil
            }
            viewport.lastActiveWorkspaceByProject = viewport.lastActiveWorkspaceByProject.filter { _, id in
                id != workspace.id
            }
            monitorViewportsById[viewportId] = viewport
        }
        return removedViewport
    }

    mutating func ensureProjectExists(_ projectId: WorkspaceProjectId) {
        if projectsById[projectId] == nil {
            let order = nextProjectOrder()
            registerProject(WorkspaceProject(id: projectId, name: "Project", order: order))
        }
        ensureUnfoldedFolderExists(for: projectId)
    }

    mutating func ensureUnfoldedFolderExists(for projectId: WorkspaceProjectId) {
        guard let project = projectsById[projectId] else { return }
        let folderId = project.unfoldedFolderId
        if workspaceFoldersById[folderId] == nil {
            let order = nextFolderOrder()
            workspaceFoldersById[folderId] = WorkspaceFolder(
                id: folderId,
                projectId: projectId,
                name: workspaceDefaultFolderDisplayName,
                order: order
            )
            nextFolderOrderCounter = max(nextFolderOrderCounter, order + 1)
            insertFolder(folderId, intoProject: projectId)
        } else if workspaceFoldersById[folderId]?.projectId != projectId {
            var folder = workspaceFoldersById[folderId].orDie()
            folder.projectId = projectId
            workspaceFoldersById[folderId] = folder
            insertFolder(folderId, intoProject: projectId)
        }
    }

    func unfoldedFolderId(for projectId: WorkspaceProjectId) -> WorkspaceFolderId {
        projectsById[projectId]?.unfoldedFolderId ?? workspaceProjectUnfoldedFolderId(projectId)
    }

    mutating func ensureFolderExists(_ folderId: WorkspaceFolderId, projectId: WorkspaceProjectId = workspaceProjectDefaultId) {
        if workspaceFoldersById[folderId] == nil {
            let order = nextFolderOrder()
            registerFolder(WorkspaceFolder(id: folderId, projectId: projectId, name: "Folder", order: order))
        } else if let folder = workspaceFoldersById[folderId] {
            ensureProjectExists(folder.projectId)
            insertFolder(folderId, intoProject: folder.projectId)
        }
    }

    mutating func ensureMonitorViewportExists(_ viewportId: MonitorViewportId) {
        if monitorViewportsById[viewportId] == nil {
            monitorViewportsById[viewportId] = MonitorViewport(id: viewportId)
        }
    }

    mutating func activeProjectId(for monitor: Monitor) -> WorkspaceProjectId {
        let viewportId = MonitorViewportId(monitor)
        ensureMonitorViewportExists(viewportId)
        return monitorViewportsById[viewportId]?.activeWorkspaceId
            .flatMap { workspaceById[$0] }
            .flatMap { workspaceFoldersById[$0.folderId]?.projectId }
            ?? projectsById[workspaceProjectDefaultId].map { _ in workspaceProjectDefaultId }
            ?? projectsById.values.sorted(by: workspaceProjectOrderPrecedes).first?.id
            ?? workspaceProjectDefaultId
    }

    mutating func visibleWorkspace(for monitor: Monitor) -> Workspace? {
        let viewportId = MonitorViewportId(monitor)
        ensureMonitorViewportExists(viewportId)
        return monitorViewportsById[viewportId]?.activeWorkspaceId.flatMap { workspaceById[$0] }
    }

    func isWorkspaceActive(_ workspaceId: WorkspaceId, outside viewportId: MonitorViewportId) -> Bool {
        monitorViewportsById.contains { otherViewportId, viewport in
            otherViewportId != viewportId && viewport.activeWorkspaceId == workspaceId
        }
    }

    mutating func setActiveWorkspace(_ workspace: Workspace, on viewportId: MonitorViewportId) -> Bool {
        ensureMonitorViewportExists(viewportId)
        ensureFolderExists(workspace.folderId)

        var viewport = monitorViewportsById[viewportId] ?? MonitorViewport(id: viewportId)
        if viewport.activeWorkspaceId != workspace.id {
            viewport.previousWorkspaceId = viewport.activeWorkspaceId
        }
        viewport.activeWorkspaceId = workspace.id
        let projectId = workspaceFoldersById[workspace.folderId]?.projectId ?? workspaceProjectDefaultId
        viewport.lastActiveWorkspaceByProject[projectId] = workspace.id
        monitorViewportsById[viewportId] = viewport
        return true
    }

    mutating func assignWorkspace(_ workspace: Workspace, to projectId: WorkspaceProjectId) {
        ensureProjectExists(projectId)
        assignWorkspace(workspace, toFolder: unfoldedFolderId(for: projectId))
    }

    mutating func assignWorkspace(_ workspace: Workspace, toFolder folderId: WorkspaceFolderId) {
        ensureFolderExists(folderId)
        removeWorkspaceFromFolderIndexes(workspace.id)
        workspace.setFolderIdFromWorkspaceState(folderId)
        insertWorkspace(workspace.id, intoFolder: folderId)
    }

    @discardableResult
    mutating func moveFolder(_ folderId: WorkspaceFolderId, toProject destinationProjectId: WorkspaceProjectId) -> Bool {
        guard var folder = workspaceFoldersById[folderId],
              folder.projectId != destinationProjectId,
              let sourceProject = projectsById[folder.projectId],
              projectsById[destinationProjectId] != nil,
              folderId != sourceProject.unfoldedFolderId
        else { return false }

        let sourceProjectId = folder.projectId
        folder.projectId = destinationProjectId
        workspaceFoldersById[folderId] = folder
        insertFolder(folderId, intoProject: destinationProjectId)
        normalizeProjectFolderOrders()
        reindexFolders(in: sourceProjectId)
        reindexFolders(in: destinationProjectId)
        return true
    }

    mutating func reorderWorkspace(_ workspaceId: WorkspaceId, inProject projectId: WorkspaceProjectId, destination: WorkspaceOrderDestination) -> Bool {
        reorderWorkspace(
            workspaceId,
            inFolder: unfoldedFolderId(for: projectId),
            destination: destination
        )
    }

    mutating func reorderWorkspace(_ workspaceId: WorkspaceId, inFolder folderId: WorkspaceFolderId, destination: WorkspaceOrderDestination) -> Bool {
        pruneProjectWorkspaceIndexes()
        guard var folder = workspaceFoldersById[folderId],
              let workspace = workspaceById[workspaceId],
              workspace.folderId == folderId,
              !workspace.isArchived
        else { return false }

        let targetWorkspaceId = destination.targetWorkspaceId
        guard workspaceId != targetWorkspaceId,
              let targetWorkspace = workspaceById[targetWorkspaceId],
              targetWorkspace.folderId == folderId,
              !targetWorkspace.isArchived
        else { return false }

        var reordered = folder.workspaceOrder
        guard reordered.contains(workspaceId), reordered.contains(targetWorkspaceId) else { return false }
        reordered.removeAll { $0 == workspaceId }
        guard let targetIndex = reordered.firstIndex(of: targetWorkspaceId) else { return false }

        let insertionIndex = switch destination {
            case .before(_): targetIndex
            case .after(_): targetIndex + 1
        }
        reordered.insert(workspaceId, at: insertionIndex)
        guard reordered != folder.workspaceOrder else { return false }

        folder.workspaceOrder = reordered
        workspaceFoldersById[folderId] = folder
        return true
    }

    mutating func reorderWorkspaces(_ workspaceIds: [WorkspaceId], inProject projectId: WorkspaceProjectId, before anchorWorkspaceId: WorkspaceId?) {
        reorderWorkspaces(
            workspaceIds,
            inFolder: unfoldedFolderId(for: projectId),
            before: anchorWorkspaceId
        )
    }

    mutating func reorderWorkspaces(_ workspaceIds: [WorkspaceId], inFolder folderId: WorkspaceFolderId, before anchorWorkspaceId: WorkspaceId?) {
        pruneProjectWorkspaceIndexes()
        guard var folder = workspaceFoldersById[folderId] else { return }
        var orderedIds: [WorkspaceId] = []
        var seen: Set<WorkspaceId> = []
        for workspaceId in workspaceIds {
            guard let workspace = workspaceById[workspaceId],
                  workspace.folderId == folderId,
                  !workspace.isArchived,
                  seen.insert(workspaceId).inserted
            else { continue }
            orderedIds.append(workspaceId)
        }
        guard !orderedIds.isEmpty else { return }

        var remainingOrder = folder.workspaceOrder.filter { !seen.contains($0) }
        let insertionIndex = anchorWorkspaceId
            .flatMap { remainingOrder.firstIndex(of: $0) }
            ?? remainingOrder.count
        remainingOrder.insert(contentsOf: orderedIds, at: insertionIndex)
        folder.workspaceOrder = remainingOrder
        workspaceFoldersById[folderId] = folder
    }

    mutating func pruneProjectWorkspaceIndexes() {
        for workspace in workspaceById.values {
            ensureFolderExists(workspace.folderId)
        }
        for (viewportId, viewport) in monitorViewportsById {
            var viewport = viewport
            if viewport.activeWorkspaceId.flatMap({ workspaceById[$0] }) == nil {
                viewport.activeWorkspaceId = nil
            }
            if viewport.previousWorkspaceId.flatMap({ workspaceById[$0] }) == nil {
                viewport.previousWorkspaceId = nil
            }
            viewport.lastActiveWorkspaceByProject = viewport.lastActiveWorkspaceByProject.filter { projectId, workspaceId in
                workspaceById[workspaceId].flatMap { workspaceFoldersById[$0.folderId]?.projectId } == projectId
            }
            monitorViewportsById[viewportId] = viewport
        }

        let orderedWorkspaces = workspaceById.values.sorted()
        for (folderId, folder) in workspaceFoldersById {
            var normalizedOrder = folder.workspaceOrder
            var seen: Set<WorkspaceId> = []
            normalizedOrder = normalizedOrder.filter { workspaceId in
                guard let workspace = workspaceById[workspaceId],
                      workspace.folderId == folderId,
                      !seen.contains(workspaceId)
                else {
                    return false
                }
                seen.insert(workspaceId)
                return true
            }
            for workspace in orderedWorkspaces where workspace.folderId == folderId && !seen.contains(workspace.id) {
                normalizedOrder.append(workspace.id)
                seen.insert(workspace.id)
            }
            guard normalizedOrder != folder.workspaceOrder else { continue }
            var normalizedFolder = folder
            normalizedFolder.workspaceOrder = normalizedOrder
            workspaceFoldersById[folderId] = normalizedFolder
        }
        normalizeProjectFolderOrders()
    }

    private mutating func rebuildFolderWorkspaceIndexes() {
        for (folderId, folder) in workspaceFoldersById {
            var folder = folder
            folder.workspaceOrder = []
            workspaceFoldersById[folderId] = folder
        }
        for workspace in workspaceById.values.sorted() {
            ensureFolderExists(workspace.folderId)
            insertWorkspace(workspace.id, intoFolder: workspace.folderId)
        }
        for (viewportId, viewport) in monitorViewportsById {
            guard let workspaceId = viewport.activeWorkspaceId,
                  let workspace = workspaceById[workspaceId]
            else { continue }
            var viewport = viewport
            let projectId = workspaceFoldersById[workspace.folderId]?.projectId ?? workspaceProjectDefaultId
            viewport.lastActiveWorkspaceByProject[projectId] = workspaceId
            monitorViewportsById[viewportId] = viewport
        }
    }

    private mutating func insertFolder(_ folderId: WorkspaceFolderId, intoProject projectId: WorkspaceProjectId) {
        for (otherProjectId, otherProject) in projectsById where otherProjectId != projectId && otherProject.folderOrder.contains(folderId) {
            var otherProject = otherProject
            otherProject.folderOrder.removeAll { $0 == folderId }
            projectsById[otherProjectId] = otherProject
        }
        var project = projectsById[projectId].orDie()
        guard !project.folderOrder.contains(folderId) else { return }
        if folderId != project.unfoldedFolderId,
           let unfoldedIndex = project.folderOrder.firstIndex(of: project.unfoldedFolderId)
        {
            project.folderOrder.insert(folderId, at: unfoldedIndex)
        } else {
            project.folderOrder.append(folderId)
        }
        projectsById[projectId] = project
    }

    private mutating func reindexFolders(in projectId: WorkspaceProjectId) {
        guard let project = projectsById[projectId] else { return }
        for (offset, folderId) in project.folderOrder.enumerated() {
            guard var folder = workspaceFoldersById[folderId] else { continue }
            folder.order = offset
            workspaceFoldersById[folderId] = folder
        }
    }

    mutating func removeFolder(_ folderId: WorkspaceFolderId) {
        workspaceFoldersById.removeValue(forKey: folderId)
        for (projectId, project) in projectsById where project.folderOrder.contains(folderId) {
            var project = project
            project.folderOrder.removeAll { $0 == folderId }
            projectsById[projectId] = project
        }
    }

    mutating func removeProject(_ projectId: WorkspaceProjectId) {
        let folderIds = Set(workspaceFoldersById.values.filter { $0.projectId == projectId }.map(\.id))
        for folderId in folderIds {
            workspaceFoldersById.removeValue(forKey: folderId)
        }
        projectsById.removeValue(forKey: projectId)
        for (viewportId, viewport) in monitorViewportsById {
            var viewport = viewport
            viewport.lastActiveWorkspaceByProject.removeValue(forKey: projectId)
            monitorViewportsById[viewportId] = viewport
        }
    }

    @discardableResult
    mutating func normalizeDefaultProjectFolderOrder() -> Bool {
        normalizeProjectFolderOrder(workspaceProjectDefaultId)
    }

    @discardableResult
    mutating func normalizeProjectFolderOrders() -> Bool {
        var didChange = false
        for projectId in projectsById.keys.sorted() {
            didChange = normalizeProjectFolderOrder(projectId) || didChange
        }
        return didChange
    }

    @discardableResult
    private mutating func normalizeProjectFolderOrder(_ projectId: WorkspaceProjectId) -> Bool {
        guard var project = projectsById[projectId] else { return false }
        var seen: Set<WorkspaceFolderId> = []
        var orderedIds = project.folderOrder.filter { folderId in
            workspaceFoldersById[folderId]?.projectId == projectId && seen.insert(folderId).inserted
        }
        let missingIds = workspaceFoldersById.values
            .filter { $0.projectId == projectId && !seen.contains($0.id) }
            .sorted(by: workspaceFolderOrderPrecedes)
            .map(\.id)
        orderedIds.append(contentsOf: missingIds)
        if orderedIds.contains(project.unfoldedFolderId) {
            orderedIds.removeAll { $0 == project.unfoldedFolderId }
            orderedIds.append(project.unfoldedFolderId)
        } else if workspaceFoldersById[project.unfoldedFolderId]?.projectId == projectId {
            orderedIds.append(project.unfoldedFolderId)
        }
        guard project.folderOrder != orderedIds else { return false }
        project.folderOrder = orderedIds
        projectsById[projectId] = project
        return true
    }

    private mutating func insertWorkspace(_ workspaceId: WorkspaceId, intoFolder folderId: WorkspaceFolderId) {
        var folder = workspaceFoldersById[folderId].orDie()
        guard !folder.workspaceOrder.contains(workspaceId) else { return }
        folder.workspaceOrder.append(workspaceId)
        workspaceFoldersById[folderId] = folder
    }

    private mutating func removeWorkspaceFromFolderIndexes(_ workspaceId: WorkspaceId) {
        for (folderId, folder) in workspaceFoldersById {
            guard folder.workspaceOrder.contains(workspaceId) else { continue }
            var folder = folder
            folder.workspaceOrder = folder.workspaceOrder.filter { $0 != workspaceId }
            workspaceFoldersById[folderId] = folder
        }
    }
}

@MainActor var winMuxWorkspaceState = WinMuxWorkspaceState()
