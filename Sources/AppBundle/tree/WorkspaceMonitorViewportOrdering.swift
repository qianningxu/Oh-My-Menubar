import AppKit

@MainActor func getOrCreateMonitorViewportFallbackWorkspace(for monitor: Monitor) -> Workspace {
    getOrCreateMonitorViewportFallbackWorkspace(
        projectId: activeWorkspaceProjectId(for: monitor),
        for: monitor,
    )
}

@MainActor func getOrCreateMonitorViewportFallbackWorkspace(projectId: WorkspaceProjectId, for monitor: Monitor) -> Workspace {
    getOrCreateFallbackWorkspace(
        projectId: projectId,
        monitor: monitor,
        excluding: nil,
    )
}

@MainActor func getOrCreateMonitorViewportFallbackWorkspace(
    projectId: WorkspaceProjectId,
    for monitor: Monitor,
    excluding excludedWorkspace: Workspace?,
) -> Workspace {
    getOrCreateFallbackWorkspace(
        projectId: projectId,
        monitor: monitor,
        excluding: excludedWorkspace,
    )
}

@MainActor
func getOrCreateMonitorViewportFallbackWorkspace(forPoint point: CGPoint) -> Workspace {
    let monitor = point.monitorApproximation
    return getOrCreateFallbackWorkspace(
        projectId: activeWorkspaceProjectId(for: monitor),
        monitor: monitor,
        excluding: nil,
    )
}

@MainActor
func getOrCreateFallbackWorkspace(
    projectId: WorkspaceProjectId,
    monitor: Monitor,
    excluding excludedWorkspace: Workspace?,
    excludingIds: Set<WorkspaceId> = [],
) -> Workspace {
    let scope = WorkspaceScope(projectId: projectId, monitor: monitor)
    if let workspaceId = retainedEmptyWorkspaceId(in: scope),
       let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
       workspace != excludedWorkspace,
       !excludingIds.contains(workspace.id),
       workspaceIsAvailableForMonitor(workspace, monitor: monitor)
    {
        return workspace
    }
    if let workspace = projectWorkspaces(projectId: projectId)
        .first(where: {
            $0 != excludedWorkspace &&
                !excludingIds.contains($0.id) &&
                $0.isEffectivelyEmpty &&
                !$0.isArchived &&
                workspaceIsAvailableForMonitor($0, monitor: monitor)
        })
    {
        return workspace
    }
    let workspace = Workspace.get(byName: nextAutomaticWorkspaceName(projectId: projectId, monitor: monitor))
    workspace.markAsTransientBlank()
    workspace.assignProject(projectId)
    workspace.seedMonitorIfNeeded(monitor)
    return workspace
}

@MainActor
func projectWorkspaces(projectId: WorkspaceProjectId) -> [Workspace] {
    winMuxWorkspaceState.pruneProjectWorkspaceIndexes()
    var seen: Set<WorkspaceId> = []
    var result: [Workspace] = []
    for folder in workspaceFoldersInSidebarOrder(projectId: projectId) {
        for workspaceId in folder.workspaceOrder {
            guard let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
                  workspace.folderId == folder.id,
                  seen.insert(workspaceId).inserted
            else { continue }
            result.append(workspace)
        }
    }
    result.append(contentsOf: Workspace.all.filter {
        $0.projectId == projectId && seen.insert($0.id).inserted
    })
    return result
}

@MainActor
func orderedWorkspaces(in scope: WorkspaceScope) -> [Workspace] {
    projectWorkspaces(projectId: scope.projectId)
        .filter { workspace in
            guard let monitorViewportId = scope.monitorViewportId else { return true }
            guard let workspaceMonitorViewportId = workspace.workspaceMonitorViewportIdForOrdering else {
                return true
            }
            return workspaceMonitorViewportId == monitorViewportId
        }
        .filter { !$0.isArchived }
}

@MainActor
func orderedWorkspaces(in projectId: WorkspaceProjectId) -> [Workspace] {
    projectWorkspaces(projectId: projectId)
        .filter { !$0.isArchived }
}

@MainActor
func orderedWorkspacesForPresentation() -> [Workspace] {
    winMuxWorkspaceState.pruneProjectWorkspaceIndexes()
    return orderedWorkspacesForPresentationFromPreparedHierarchy(workspaceProjects())
}

@MainActor
func orderedWorkspacesForPresentationFromPreparedHierarchy(
    _ projects: [WorkspaceProject]
) -> [Workspace] {
    var seen: Set<WorkspaceId> = []
    var result: [Workspace] = []
    for project in projects {
        for folder in workspaceFoldersInSidebarOrder(projectId: project.id) {
            for workspaceId in folder.workspaceOrder {
                guard let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
                      !workspace.isArchived,
                      seen.insert(workspaceId).inserted
                else { continue }
                result.append(workspace)
            }
        }
    }
    result.append(contentsOf: Workspace.all.filter { !$0.isArchived && seen.insert($0.id).inserted })
    return result
}

@MainActor
private func orderedWorkspacesAcrossProjectIndexes() -> [Workspace] {
    winMuxWorkspaceState.pruneProjectWorkspaceIndexes()
    var seen: Set<WorkspaceId> = []
    var result: [Workspace] = []
    winMuxWorkspaceState.normalizeDefaultProjectFolderOrder()
    let folders = workspaceFoldersInSidebarOrder()
    for folder in folders {
        for workspaceId in folder.workspaceOrder {
            guard let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
                  !workspace.isArchived,
                  seen.insert(workspaceId).inserted
            else { continue }
            result.append(workspace)
        }
    }
    result.append(contentsOf: Workspace.all.filter { !$0.isArchived && seen.insert($0.id).inserted })
    return result
}
