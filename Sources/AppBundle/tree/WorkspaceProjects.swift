import AppKit
import Common

@MainActor
func projectsAreEnabled() -> Bool {
    config.enableProjects
}

@MainActor
func projectFeatureDisabledMessage() -> String { "Projects are disabled by enable-projects = false" }

@MainActor
func workspaceFolders(in projectId: WorkspaceProjectId? = nil) -> [WorkspaceFolder] {
    materializePersistedWorkspaceProjects()
    winMuxWorkspaceState.normalizeProjectFolderOrders()
    return workspaceFoldersFromPreparedHierarchy(
        in: projectId,
        orderedProjects: workspaceProjectsFromMaterializedState()
    )
}

@MainActor
private func workspaceFoldersFromPreparedHierarchy(
    in projectId: WorkspaceProjectId? = nil,
    orderedProjects: [WorkspaceProject]
) -> [WorkspaceFolder] {
    let folders: [WorkspaceFolder]
    if let projectId {
        folders = workspaceFoldersInSidebarOrder(projectId: projectId)
    } else {
        folders = orderedProjects.flatMap { workspaceFoldersInSidebarOrder(projectId: $0.id) }
    }
    return folders.map { folder in
        let displayName: String
        if let configuredName = config.workspaceSidebar.folderLabels[folder.id.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredName.isEmpty,
           configuredName != folder.id.rawValue
        {
            displayName = workspaceSidebarFolderDisplayName(configuredName)
        } else if folder.id == winMuxWorkspaceState.projectsById[folder.projectId]?.unfoldedFolderId {
            displayName = workspaceDefaultFolderDisplayName
        } else {
            // A durable sidebar snapshot may be the only source for a custom
            // folder name after browser windows receive new macOS IDs.
            displayName = workspaceSidebarFolderDisplayName(folder.name)
        }
        return WorkspaceFolder(
            id: folder.id,
            projectId: folder.projectId,
            name: displayName,
            order: folder.order,
            workspaceOrder: folder.workspaceOrder,
            linkedViewportIds: folder.linkedViewportIds,
        )
    }
}

@MainActor
func workspaceFolders() -> [WorkspaceFolder] {
    workspaceFolders(in: nil)
}

@MainActor
func workspaceFoldersInSidebarOrder(projectId: WorkspaceProjectId = workspaceProjectDefaultId) -> [WorkspaceFolder] {
    let folderById = winMuxWorkspaceState.workspaceFoldersById
    let orderedIds = winMuxWorkspaceState.projectsById[projectId]?.folderOrder ?? []
    var seen: Set<WorkspaceFolderId> = []
    var folders = orderedIds.compactMap { folderId -> WorkspaceFolder? in
        guard let folder = folderById[folderId],
              seen.insert(folderId).inserted
        else { return nil }
        return folder
    }
    folders.append(contentsOf: folderById.values
        .filter { $0.projectId == projectId && seen.insert($0.id).inserted }
        .sorted(by: workspaceFolderOrderPrecedes))
    return folders
}

@MainActor
func workspaceFolderName(_ folderId: WorkspaceFolderId) -> String {
    workspaceFolders().first { $0.id == folderId }?.name ?? "Folder"
}

@MainActor
func workspaceFolderDisplayName(_ folderId: WorkspaceFolderId, fallbackName: String) -> String {
    workspaceFolders().first { $0.id == folderId }?.name ?? fallbackName
}

@MainActor
func activeWorkspaceFolderId(for monitor: Monitor) -> WorkspaceFolderId {
    winMuxWorkspaceState.visibleWorkspace(for: monitor)?.folderId ?? workspaceFolderDefaultId
}

@MainActor
func createWorkspaceFolder(in projectId: WorkspaceProjectId = workspaceProjectDefaultId) -> WorkspaceFolder {
    materializePersistedWorkspaceProjects()
    winMuxWorkspaceState.ensureProjectExists(projectId)
    let identity = winMuxWorkspaceState.nextGeneratedFolderIdentity()
    let order = winMuxWorkspaceState.nextFolderOrder()
    let folder = WorkspaceFolder(id: identity.id, projectId: projectId, name: identity.name, order: order)
    winMuxWorkspaceState.registerFolder(folder)
    config.workspaceSidebar.folderLabels[folder.id.rawValue] = folder.name
    if !isUnitTest {
        try? persistWorkspaceSidebarFolderLabel(folderId: folder.id.rawValue, label: folder.name)
    }
    return winMuxWorkspaceState.workspaceFoldersById[folder.id] ?? folder
}

@MainActor
func switchWorkspaceFolder(_ folderId: WorkspaceFolderId, on monitor: Monitor) -> Workspace? {
    if let workspace = sidebarPreferredWorkspace(folderId: folderId, monitor: monitor) {
        return activateWorkspaceOnMonitorPreservingSourceViewport(workspace, targetMonitor: monitor)
            ? workspace
            : nil
    }
    guard let folder = winMuxWorkspaceState.workspaceFoldersById[folderId] else { return nil }
    let workspace = createBlankWorkspace(folderId: folder.id, monitor: monitor)
    return activateWorkspaceOnMonitorPreservingSourceViewport(workspace, targetMonitor: monitor)
        ? workspace
        : nil
}

@MainActor
func folderWorkspaces(folderId: WorkspaceFolderId) -> [Workspace] {
    guard let folder = winMuxWorkspaceState.workspaceFoldersById[folderId] else { return [] }
    let indexed = folder.workspaceOrder.compactMap { winMuxWorkspaceState.workspaceById[$0] }
        .filter { $0.folderId == folderId && !$0.isArchived }
    return indexed.isEmpty
        ? Workspace.all.filter { $0.folderId == folderId && !$0.isArchived }.sorted()
        : indexed
}

@MainActor
private func sidebarPreferredWorkspace(folderId: WorkspaceFolderId, monitor: Monitor) -> Workspace? {
    let candidates = userFacingWorkspaces(orderedWorkspacesForPresentation(), focusedWorkspace: focus.workspace)
        .filter {
            $0.folderId == folderId &&
                isValidAssignment(workspace: $0, screen: monitor.rect.topLeftCorner)
        }
    let monitorLocalCandidates = candidates.filter {
        !$0.isVisible || $0.workspaceMonitor.rect.topLeftCorner == monitor.rect.topLeftCorner
    }
    let preferredWorkspace = monitorLocalCandidates.first(where: workspaceHasSidebarVisibleWindows) ??
        candidates.first(where: workspaceHasSidebarVisibleWindows) ??
        monitorLocalCandidates.first ??
        candidates.first
    let rememberedWorkspace = winMuxWorkspaceState.monitorViewportsById[MonitorViewportId(monitor)]?
        .lastActiveWorkspaceByProject[winMuxWorkspaceState.workspaceFoldersById[folderId]?.projectId ?? workspaceProjectDefaultId]
        .flatMap { rememberedId in candidates.first { $0.id == rememberedId } }
        .flatMap { remembered in
            workspaceHasSidebarVisibleWindows(remembered) ||
                remembered.isConfiguredPersistent ||
                !workspaceOwnedMinimizedWindows(remembered).isEmpty ||
                preferredWorkspace == nil ||
                preferredWorkspace === remembered
                ? remembered
                : nil
        }
    return rememberedWorkspace ?? preferredWorkspace
}

@MainActor
func workspaceProjects() -> [WorkspaceProject] {
    materializePersistedWorkspaceProjectMetadata()
    return workspaceProjectsFromMaterializedState()
}

@MainActor
private func workspaceProjectsFromMaterializedState() -> [WorkspaceProject] {
    return winMuxWorkspaceState.projectsById.values.sorted(by: workspaceProjectOrderPrecedes).map { project in
        var project = project
        if let configuredName = config.workspaceSidebar.projectLabels[project.id.rawValue]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !configuredName.isEmpty
        {
            project.name = configuredName
        }
        return project
    }
}

@MainActor
func workspaceProjectName(_ projectId: WorkspaceProjectId) -> String {
    workspaceProjects().first { $0.id == projectId }?.name ?? "Project"
}

@MainActor
func workspaceProjectDisplayName(_ projectId: WorkspaceProjectId, fallbackName: String) -> String {
    workspaceProjects().first { $0.id == projectId }?.name ?? fallbackName
}

@MainActor
func activeWorkspaceProjectId(for monitor: Monitor) -> WorkspaceProjectId {
    materializePersistedWorkspaceProjects()
    return winMuxWorkspaceState.activeProjectId(for: monitor)
}

@MainActor
func createWorkspaceProject(displayName: String? = nil) -> WorkspaceProject {
    let identity = winMuxWorkspaceState.nextGeneratedProjectIdentity()
    let project = WorkspaceProject(
        id: identity.id,
        name: displayName ?? identity.name,
        order: winMuxWorkspaceState.nextProjectOrder()
    )
    winMuxWorkspaceState.registerProject(project)
    winMuxWorkspaceState.ensureUnfoldedFolderExists(for: project.id)
    config.workspaceSidebar.projectLabels[project.id.rawValue] = project.name
    if !isUnitTest {
        try? persistWorkspaceSidebarProjectLabel(projectId: project.id.rawValue, label: project.name)
    }
    ensureMinimumWorkspace(for: project.id)
    return winMuxWorkspaceState.projectsById[project.id] ?? project
}

func workspaceProjectOrderPrecedes(_ lhs: WorkspaceProject, _ rhs: WorkspaceProject) -> Bool {
    if lhs.order != rhs.order {
        return lhs.order < rhs.order
    }
    return lhs.id < rhs.id
}

func workspaceFolderOrderPrecedes(_ lhs: WorkspaceFolder, _ rhs: WorkspaceFolder) -> Bool {
    if lhs.order != rhs.order {
        return lhs.order < rhs.order
    }
    return lhs.id < rhs.id
}

@MainActor
func materializePersistedWorkspaceProjects() {
    materializePersistedWorkspaceProjectMetadata()
    ensureMinimumWorkspaceForAllProjects()
}

struct WorkspaceSidebarHierarchyInputs {
    let projects: [WorkspaceProject]
    let folders: [WorkspaceFolder]
    let orderedWorkspaces: [Workspace]
}

@MainActor
func prepareWorkspaceSidebarHierarchyInputs() -> WorkspaceSidebarHierarchyInputs {
    // Repair hierarchy state once before the downstream builders read it.
    materializePersistedWorkspaceProjects()
    pruneEmptyWorkspaceTabGroups()

    let projects = workspaceProjectsFromMaterializedState()
    return WorkspaceSidebarHierarchyInputs(
        projects: projects,
        folders: workspaceFoldersFromPreparedHierarchy(orderedProjects: projects),
        orderedWorkspaces: orderedWorkspacesForPresentationFromPreparedHierarchy(projects),
    )
}

@MainActor
private func materializePersistedWorkspaceProjectMetadata() {
    for rawProjectId in Set(config.workspaceSidebar.projectLabels.keys)
        .union(config.workspaceSidebar.projectColors.keys).sorted()
    where rawProjectId != workspaceProjectDefaultId.rawValue {
        let projectId = WorkspaceProjectId(rawProjectId)
        guard winMuxWorkspaceState.projectsById[projectId] == nil else { continue }
        let name = config.workspaceSidebar.projectLabels[rawProjectId]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Project"
        guard !name.isEmpty else { continue }
        winMuxWorkspaceState.registerProject(WorkspaceProject(
            id: projectId,
            name: name,
            order: winMuxWorkspaceState.nextProjectOrder()
        ))
        winMuxWorkspaceState.ensureUnfoldedFolderExists(for: projectId)
    }
    for rawFolderId in Set(config.workspaceSidebar.folderLabels.keys)
        .union(config.workspaceSidebar.folderColors.keys).sorted()
    {
        let folderId = WorkspaceFolderId(rawFolderId)
        guard winMuxWorkspaceState.workspaceFoldersById[folderId] == nil else { continue }
        let name = config.workspaceSidebar.folderLabels[rawFolderId]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Folder"
        guard !name.isEmpty else { continue }
        winMuxWorkspaceState.registerFolder(WorkspaceFolder(
            id: folderId,
            projectId: workspaceProjectDefaultId,
            name: name,
            order: winMuxWorkspaceState.nextFolderOrder()
        ))
    }
}

@MainActor
func ensureMinimumWorkspaceForAllProjects(monitor: Monitor = mainMonitor) {
    for projectId in winMuxWorkspaceState.projectsById.keys {
        ensureMinimumWorkspace(for: projectId, monitor: monitor)
    }
}

@MainActor
func ensureMinimumWorkspace(for projectId: WorkspaceProjectId, monitor: Monitor = mainMonitor) {
    winMuxWorkspaceState.ensureProjectExists(projectId)
    guard !Workspace.all.contains(where: { $0.projectId == projectId && !$0.isArchived }) else { return }
    _ = createBlankWorkspace(projectId: projectId, monitor: monitor)
}

@MainActor
func renameWorkspaceForSidebar(workspaceName: String, displayName: String) throws {
    guard Workspace.existing(byName: workspaceName) != nil else {
        throw WorkspaceMutationError.workspaceNotFound(workspaceName)
    }
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
        throw WorkspaceMutationError.emptyName
    }
    if trimmedName == workspaceDefaultDisplayName(workspaceName) {
        try resetWorkspaceSidebarName(workspaceName: workspaceName)
        return
    }
    config.workspaceSidebar.workspaceLabels[workspaceName] = trimmedName
    if !isUnitTest {
        try persistWorkspaceSidebarLabel(workspaceName: workspaceName, label: trimmedName)
        persistSidebarStateForRestartIfPossible()
    }
}

@MainActor
@discardableResult
func reorderWorkspaceForSidebar(
    sourceWorkspaceName: String,
    projectId: WorkspaceProjectId,
    placement: WorkspaceReorderPlacement
) -> Bool {
    reorderWorkspaceForSidebar(
        sourceWorkspaceName: sourceWorkspaceName,
        folderId: WorkspaceFolderId(projectId),
        placement: placement
    )
}

@MainActor
@discardableResult
func reorderWorkspaceForSidebar(
    sourceWorkspaceName: String,
    folderId: WorkspaceFolderId,
    placement: WorkspaceReorderPlacement
) -> Bool {
    materializePersistedWorkspaceProjects()
    guard let source = Workspace.existing(byName: sourceWorkspaceName),
          let target = Workspace.existing(byName: placement.targetWorkspaceName),
          !source.isArchived,
          !target.isArchived
    else { return false }

    guard target.folderId == folderId,
          let destinationFolder = winMuxWorkspaceState.workspaceFoldersById[folderId],
          source.projectId == destinationFolder.projectId
    else { return false }

    if source.folderId != folderId {
        return moveWorkspaceForSidebarReorder(
            source: source,
            target: target,
            destinationFolderId: folderId,
            placement: placement
        )
    }

    let destination: WorkspaceOrderDestination = switch placement {
        case .before(_): .before(target.id)
        case .after(_): .after(target.id)
    }
    return winMuxWorkspaceState.reorderWorkspace(source.id, inFolder: folderId, destination: destination)
}

@MainActor
private func moveWorkspaceForSidebarReorder(
    source: Workspace,
    target: Workspace,
    destinationFolderId: WorkspaceFolderId,
    placement: WorkspaceReorderPlacement
) -> Bool {
    guard source != target,
          target.folderId == destinationFolderId,
          let destinationFolder = winMuxWorkspaceState.workspaceFoldersById[destinationFolderId],
          source.projectId == destinationFolder.projectId
    else { return false }
    source.assignFolder(destinationFolderId)
    guard var folder = winMuxWorkspaceState.workspaceFoldersById[destinationFolderId] else { return false }
    folder.workspaceOrder.removeAll { $0 == source.id }
    guard let targetIndex = folder.workspaceOrder.firstIndex(of: target.id) else { return false }
    let insertionIndex = switch placement {
        case .before(_): targetIndex
        case .after(_): targetIndex + 1
    }
    folder.workspaceOrder.insert(source.id, at: insertionIndex)
    winMuxWorkspaceState.workspaceFoldersById[destinationFolderId] = folder
    setWorkspaceSidebarFolderExpanded(destinationFolderId, isExpanded: true)
    checkWorkspaceHierarchyInvariants()
    return true
}

@MainActor
func resetWorkspaceSidebarName(workspaceName: String) throws {
    guard Workspace.existing(byName: workspaceName) != nil else {
        throw WorkspaceMutationError.workspaceNotFound(workspaceName)
    }
    config.workspaceSidebar.workspaceLabels.removeValue(forKey: workspaceName)
    if !isUnitTest {
        try persistWorkspaceSidebarLabel(workspaceName: workspaceName, label: nil)
        persistSidebarStateForRestartIfPossible()
    }
}

@MainActor
@discardableResult
func moveWorkspaceToProject(
    workspaceName: String,
    destinationProjectId: WorkspaceProjectId
) -> Bool {
    materializePersistedWorkspaceProjects()
    guard let workspace = Workspace.existing(byName: workspaceName),
          !workspace.isArchived,
          workspace.projectId != destinationProjectId,
          winMuxWorkspaceState.projectsById[destinationProjectId] != nil
    else { return false }

    let sourceProjectId = workspace.projectId
    let sourceMonitor = workspace.workspaceMonitor
    let fallback = workspaceFallbackForDeletion(
        excluding: workspace,
        projectId: sourceProjectId,
        monitor: sourceMonitor
    )
    if workspace.isVisible {
        guard sourceMonitor.setActiveWorkspace(fallback) else { return false }
    }
    if focus.workspace == workspace {
        _ = setFocus(to: fallback.toLiveFocus())
    }

    workspace.assignProject(destinationProjectId)
    winMuxWorkspaceState.pruneProjectWorkspaceIndexes()
    checkWorkspaceHierarchyInvariants()
    return true
}

@MainActor
@discardableResult
func moveWorkspaceFolderToProject(
    folderId: WorkspaceFolderId,
    destinationProjectId: WorkspaceProjectId
) -> Bool {
    materializePersistedWorkspaceProjects()
    guard let folder = winMuxWorkspaceState.workspaceFoldersById[folderId],
          folder.projectId != destinationProjectId,
          winMuxWorkspaceState.projectsById[destinationProjectId] != nil,
          folderId != winMuxWorkspaceState.unfoldedFolderId(for: folder.projectId)
    else { return false }

    let sourceProjectId = folder.projectId
    let movedWorkspaceIds = Set(folderWorkspaces(folderId: folderId).map(\.id))
    let visibleWorkspaces = movedWorkspaceIds.compactMap { workspaceId -> Workspace? in
        guard let workspace = winMuxWorkspaceState.workspaceById[workspaceId], workspace.isVisible else {
            return nil
        }
        return workspace
    }
    var fallbackByMovedWorkspaceId: [WorkspaceId: Workspace] = [:]
    for workspace in visibleWorkspaces {
        let fallback = workspaceFallbackForMovingFolder(
            excludingWorkspaceIds: movedWorkspaceIds,
            adjacentTo: workspace,
            projectId: sourceProjectId,
            monitor: workspace.workspaceMonitor
        )
        guard workspace.workspaceMonitor.setActiveWorkspace(fallback) else { return false }
        fallbackByMovedWorkspaceId[workspace.id] = fallback
    }
    let focusedWorkspace = focus.workspace
    if movedWorkspaceIds.contains(focusedWorkspace.id),
       let fallback = fallbackByMovedWorkspaceId[focusedWorkspace.id]
    {
        _ = setFocus(to: fallback.toLiveFocus())
    }

    guard winMuxWorkspaceState.moveFolder(folderId, toProject: destinationProjectId) else { return false }
    winMuxWorkspaceState.pruneProjectWorkspaceIndexes()
    checkWorkspaceHierarchyInvariants()
    return true
}

@MainActor
private func workspaceFallbackForMovingFolder(
    excludingWorkspaceIds: Set<WorkspaceId>,
    adjacentTo workspace: Workspace,
    projectId: WorkspaceProjectId,
    monitor: Monitor
) -> Workspace {
    let ordered = userFacingWorkspaces(
        orderedWorkspaces(in: projectId),
        focusedWorkspace: focus.workspace
    )
    if let anchorIndex = ordered.firstIndex(where: { $0 === workspace }) {
        for distance in 1 ..< ordered.count {
            let candidateIndexes = [anchorIndex - distance, anchorIndex + distance]
            if let candidate = candidateIndexes.lazy.compactMap({ index -> Workspace? in
                guard ordered.indices.contains(index) else { return nil }
                let candidate = ordered[index]
                return !excludingWorkspaceIds.contains(candidate.id) &&
                    workspaceIsAvailableForMonitor(candidate, monitor: monitor)
                    ? candidate
                    : nil
            }).first {
                return candidate
            }
        }
    }
    return getOrCreateFallbackWorkspace(
        projectId: projectId,
        monitor: monitor,
        excluding: workspace,
        excludingIds: excludingWorkspaceIds
    )
}

@MainActor
func deleteWorkspaceFolder(_ folderId: WorkspaceFolderId) throws {
    materializePersistedWorkspaceProjects()
    guard let folder = winMuxWorkspaceState.workspaceFoldersById[folderId] else {
        throw WorkspaceMutationError.projectNotFound(folderId.rawValue)
    }
    guard canDeleteWorkspaceFolder(folderId) else {
        throw WorkspaceMutationError.projectCannotBeDeleted(folder.name)
    }
    let unfoldedFolderId = winMuxWorkspaceState.unfoldedFolderId(for: folder.projectId)
    for workspace in folderWorkspaces(folderId: folderId) {
        workspace.assignFolder(unfoldedFolderId)
    }
    winMuxWorkspaceState.removeFolder(folderId)
    try clearWorkspaceSidebarFolderMetadata(folderId)
    winMuxWorkspaceState.pruneProjectWorkspaceIndexes()
    checkWorkspaceHierarchyInvariants()
}

@MainActor
private func clearWorkspaceSidebarFolderMetadata(_ folderId: WorkspaceFolderId) throws {
    let rawFolderId = folderId.rawValue
    let hadLabel = config.workspaceSidebar.folderLabels.removeValue(forKey: rawFolderId) != nil
    let hadColor = config.workspaceSidebar.folderColors.removeValue(forKey: rawFolderId) != nil
    clearWorkspaceSidebarFolderExpansionPreference(folderId)
    guard !isUnitTest else { return }
    if hadLabel {
        try persistWorkspaceSidebarFolderLabel(folderId: rawFolderId, label: nil)
    }
    if hadColor {
        try persistWorkspaceSidebarFolderColor(folderId: rawFolderId, colorHex: nil)
    }
}

@MainActor
func renameWorkspaceProject(_ projectId: WorkspaceProjectId, displayName: String) throws {
    materializePersistedWorkspaceProjects()
    guard var project = winMuxWorkspaceState.projectsById[projectId] else {
        throw WorkspaceMutationError.projectNotFound(projectId.rawValue)
    }
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw WorkspaceMutationError.emptyName }
    if workspaceProjects().contains(where: { $0.id != projectId && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
        throw WorkspaceMutationError.duplicateProjectName(trimmedName)
    }
    project.name = trimmedName
    winMuxWorkspaceState.projectsById[projectId] = project
    config.workspaceSidebar.projectLabels[projectId.rawValue] = trimmedName
    if !isUnitTest {
        try persistWorkspaceSidebarProjectLabel(projectId: projectId.rawValue, label: trimmedName)
    }
}

@MainActor
func renameWorkspaceFolder(_ folderId: WorkspaceFolderId, displayName: String) throws {
    materializePersistedWorkspaceProjects()
    guard var folder = winMuxWorkspaceState.workspaceFoldersById[folderId] else {
        throw WorkspaceMutationError.projectNotFound(folderId.rawValue)
    }
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw WorkspaceMutationError.emptyName }
    folder.name = trimmedName
    winMuxWorkspaceState.workspaceFoldersById[folderId] = folder
    config.workspaceSidebar.folderLabels[folderId.rawValue] = trimmedName
    if !isUnitTest {
        try persistWorkspaceSidebarFolderLabel(folderId: folderId.rawValue, label: trimmedName)
    }
}

@MainActor
@discardableResult
func reorderWorkspaceProjectForSidebar(
    sourceProjectId: WorkspaceProjectId,
    placement: WorkspaceSidebarFolderReorderPlacement
) -> Bool {
    materializePersistedWorkspaceProjects()
    let targetProjectId = placement.targetProjectId
    guard sourceProjectId != workspaceProjectDefaultId,
          targetProjectId != workspaceProjectDefaultId,
          sourceProjectId != targetProjectId,
          winMuxWorkspaceState.projectsById[sourceProjectId] != nil,
          winMuxWorkspaceState.projectsById[targetProjectId] != nil
    else { return false }

    let sortedProjectIds = workspaceProjects()
        .map(\.id)
        .filter { $0 != workspaceProjectDefaultId }
    guard sortedProjectIds.contains(sourceProjectId),
          sortedProjectIds.contains(targetProjectId)
    else { return false }

    var reorderedProjectIds = sortedProjectIds.filter { $0 != sourceProjectId }
    guard let targetIndex = reorderedProjectIds.firstIndex(of: targetProjectId) else { return false }
    let insertionIndex = switch placement {
        case .before: targetIndex
        case .after: targetIndex + 1
    }
    reorderedProjectIds.insert(sourceProjectId, at: insertionIndex)
    guard reorderedProjectIds != sortedProjectIds else { return false }

    for (offset, projectId) in reorderedProjectIds.enumerated() {
        guard var project = winMuxWorkspaceState.projectsById[projectId] else { continue }
        project = WorkspaceProject(
            id: project.id,
            name: project.name,
            order: offset + 1,
            unfoldedFolderId: project.unfoldedFolderId,
            folderOrder: project.folderOrder,
            linkedViewportIds: project.linkedViewportIds
        )
        winMuxWorkspaceState.projectsById[projectId] = project
    }
    checkWorkspaceHierarchyInvariants()
    return true
}

@MainActor
@discardableResult
func reorderWorkspaceFolderForSidebar(
    sourceFolderId: WorkspaceFolderId,
    placement: WorkspaceSidebarFolderReorderPlacement
) -> Bool {
    materializePersistedWorkspaceProjects()
    let targetFolderId = WorkspaceFolderId(placement.targetProjectId)
    guard sourceFolderId != targetFolderId,
          let sourceFolder = winMuxWorkspaceState.workspaceFoldersById[sourceFolderId],
          let targetFolder = winMuxWorkspaceState.workspaceFoldersById[targetFolderId],
          sourceFolder.projectId == targetFolder.projectId,
          var project = winMuxWorkspaceState.projectsById[sourceFolder.projectId],
          sourceFolderId != project.unfoldedFolderId,
          targetFolderId != project.unfoldedFolderId
    else { return false }

    var reorderedFolderIds = project.folderOrder.filter {
        $0 != sourceFolderId && $0 != project.unfoldedFolderId
    }
    guard let targetIndex = reorderedFolderIds.firstIndex(of: targetFolderId) else { return false }
    let insertionIndex = switch placement {
        case .before: targetIndex
        case .after: targetIndex + 1
    }
    reorderedFolderIds.insert(sourceFolderId, at: insertionIndex)
    reorderedFolderIds.append(project.unfoldedFolderId)
    guard reorderedFolderIds != project.folderOrder else { return false }
    project.folderOrder = reorderedFolderIds
    winMuxWorkspaceState.projectsById[project.id] = project
    for (offset, folderId) in reorderedFolderIds.enumerated() {
        guard var folder = winMuxWorkspaceState.workspaceFoldersById[folderId] else { continue }
        folder.order = offset
        winMuxWorkspaceState.workspaceFoldersById[folderId] = folder
    }
    checkWorkspaceHierarchyInvariants()
    return true
}

@MainActor
func canDeleteWorkspaceProject(_ projectId: WorkspaceProjectId) -> Bool {
    materializePersistedWorkspaceProjects()
    return winMuxWorkspaceState.projectsById[projectId] != nil
}

@MainActor
func canDeleteWorkspaceFolder(_ folderId: WorkspaceFolderId) -> Bool {
    guard let folder = winMuxWorkspaceState.workspaceFoldersById[folderId],
          let project = winMuxWorkspaceState.projectsById[folder.projectId]
    else { return false }
    return folderId != project.unfoldedFolderId
}

@MainActor
func workspaceProjectFallbackForDeletion(excluding projectId: WorkspaceProjectId) -> WorkspaceProjectId {
    let projects = workspaceProjects()
    if projects.allSatisfy({ $0.id == projectId }) {
        return createWorkspaceProject(displayName: "Default").id
    }
    guard let deletedIndex = projects.firstIndex(where: { $0.id == projectId }) else {
        return projects.first { $0.id != projectId }?.id ?? workspaceProjectDefaultId
    }
    if let next = projects.getOrNil(atIndex: deletedIndex + 1) {
        return next.id
    }
    if deletedIndex > 0 {
        return projects[deletedIndex - 1].id
    }
    return workspaceProjectDefaultId
}

@MainActor
func deleteWorkspaceForSidebar(workspaceName: String) throws {
    guard let workspace = Workspace.existing(byName: workspaceName) else {
        throw WorkspaceMutationError.workspaceNotFound(workspaceName)
    }
    try deleteWorkspace(workspace)
}

@MainActor
func closeWorkspaceWindowsFromSidebar(workspaceName: String) async throws {
    guard let workspace = Workspace.existing(byName: workspaceName) else {
        throw WorkspaceMutationError.workspaceNotFound(workspaceName)
    }

    let displayName = workspaceDisplayName(workspace.name)
    let remaining = await closeWindowsForSidebarDeletion(
        windowsInWorkspace(workspace),
        terminateAppsWhenAllWindowsIncluded: false
    )
    if !remaining.isEmpty {
        throw WorkspaceMutationError.workspaceCloseBlocked(displayName, remaining.count)
    }

    guard winMuxWorkspaceState.workspaceById[workspace.id] === workspace else { return }
    let newlyRemaining = windowsInWorkspace(workspace)
    guard newlyRemaining.isEmpty else {
        throw WorkspaceMutationError.workspaceCloseBlocked(displayName, newlyRemaining.count)
    }
    try deleteWorkspace(workspace)
}

@MainActor
func deleteWorkspaceProject(_ projectId: WorkspaceProjectId) throws {
    try deleteWorkspaceProjectMovingWindowsToFallback(projectId)
}

@MainActor
func deleteWorkspaceProjectFromSidebar(_ projectId: WorkspaceProjectId) async throws {
    switch config.workspaceSidebar.projectDeletionAction {
        case .closeWindows:
            try await closeWindowsAndDeleteWorkspaceProject(projectId)
        case .moveWindowsToFallback:
            try deleteWorkspaceProjectMovingWindowsToFallback(projectId)
    }
}

@MainActor
private func deleteWorkspaceProjectMovingWindowsToFallback(_ projectId: WorkspaceProjectId) throws {
    materializePersistedWorkspaceProjects()
    guard let project = winMuxWorkspaceState.projectsById[projectId] else {
        throw WorkspaceMutationError.projectNotFound(projectId.rawValue)
    }
    guard canDeleteWorkspaceProject(projectId) else {
        throw WorkspaceMutationError.projectCannotBeDeleted(project.name)
    }

    let fallbackId = workspaceProjectFallbackForDeletion(excluding: projectId)
    let viewportsShowingDeletedProject = winMuxWorkspaceState.monitorViewportsById.values.compactMap { viewport -> MonitorViewportId? in
        guard let activeWorkspaceId = viewport.activeWorkspaceId,
              winMuxWorkspaceState.workspaceById[activeWorkspaceId]?.projectId == projectId
        else { return nil }
        return viewport.id
    }
    for viewportId in viewportsShowingDeletedProject {
        _ = switchWorkspaceProject(fallbackId, on: viewportId.topLeftCorner.monitorApproximation)
    }

    for workspace in Workspace.all.filter({ $0.projectId == projectId }) {
        let fallback = workspaceFallbackForDeletion(
            excluding: workspace,
            projectId: fallbackId,
            monitor: workspace.workspaceMonitor,
        )
        moveWorkspaceContents(from: workspace, to: fallback)
        removeWorkspaceFromRegistry(workspace)
    }

    winMuxWorkspaceState.removeProject(projectId)
    try clearWorkspaceSidebarProjectMetadata(projectId)
    ensureVisibleActiveProjectWorkspaces()
    checkWorkspaceHierarchyInvariants()
}

@MainActor
private func closeWindowsAndDeleteWorkspaceProject(_ projectId: WorkspaceProjectId) async throws {
    materializePersistedWorkspaceProjects()
    guard let project = winMuxWorkspaceState.projectsById[projectId] else {
        throw WorkspaceMutationError.projectNotFound(projectId.rawValue)
    }
    guard canDeleteWorkspaceProject(projectId) else {
        throw WorkspaceMutationError.projectCannotBeDeleted(project.name)
    }

    let windows = windowsInWorkspaceProject(projectId)
    if !windows.isEmpty {
        let remaining = await closeWindowsForSidebarDeletion(
            windows,
            terminateAppsWhenAllWindowsIncluded: true
        )
        if !remaining.isEmpty {
            throw WorkspaceMutationError.projectCloseBlocked(project.name, remaining.count)
        }
    }

    let fallbackId = workspaceProjectFallbackForDeletion(excluding: projectId)
    let viewportsShowingDeletedProject = winMuxWorkspaceState.monitorViewportsById.values.compactMap { viewport -> MonitorViewportId? in
        guard let activeWorkspaceId = viewport.activeWorkspaceId,
              winMuxWorkspaceState.workspaceById[activeWorkspaceId]?.projectId == projectId
        else { return nil }
        return viewport.id
    }
    for viewportId in viewportsShowingDeletedProject {
        _ = switchWorkspaceProject(fallbackId, on: viewportId.topLeftCorner.monitorApproximation)
    }

    for workspace in Workspace.all.filter({ $0.projectId == projectId }) {
        removeWorkspaceFromRegistry(workspace)
    }

    winMuxWorkspaceState.removeProject(projectId)
    try clearWorkspaceSidebarProjectMetadata(projectId)
    ensureVisibleActiveProjectWorkspaces()
    checkWorkspaceHierarchyInvariants()
}

@MainActor
private func clearWorkspaceSidebarProjectMetadata(_ projectId: WorkspaceProjectId) throws {
    let rawProjectId = projectId.rawValue
    let hadLabel = config.workspaceSidebar.projectLabels.removeValue(forKey: rawProjectId) != nil
    let hadColor = config.workspaceSidebar.projectColors.removeValue(forKey: rawProjectId) != nil
    guard !isUnitTest else { return }
    if hadLabel {
        try persistWorkspaceSidebarProjectLabel(projectId: rawProjectId, label: nil)
    }
    if hadColor {
        try persistWorkspaceSidebarProjectColor(projectId: rawProjectId, colorHex: nil)
    }
}

@MainActor
private func clearOrphanedWorkspaceTabGroupMetadata() {
    var metadataProjectIds: Set<WorkspaceProjectId> = []
    for rawProjectId in config.workspaceSidebar.projectLabels.keys {
        metadataProjectIds.insert(WorkspaceProjectId(rawProjectId))
    }
    for rawProjectId in config.workspaceSidebar.projectColors.keys {
        metadataProjectIds.insert(WorkspaceProjectId(rawProjectId))
    }
    for projectId in metadataProjectIds
    where projectId != workspaceProjectDefaultId &&
        winMuxWorkspaceState.projectsById[projectId] == nil
    {
        try? clearWorkspaceSidebarProjectMetadata(projectId)
    }
}

@MainActor
func pruneEmptyWorkspaceTabGroups() {
    winMuxWorkspaceState.pruneProjectWorkspaceIndexes()
    let emptyFolderIds = winMuxWorkspaceState.workspaceFoldersById.values
        .filter { folder in
            guard let project = winMuxWorkspaceState.projectsById[folder.projectId] else { return false }
            return folder.id != project.unfoldedFolderId &&
                folder.workspaceOrder.isEmpty &&
                !winMuxWorkspaceState.workspaceById.values.contains { $0.folderId == folder.id }
        }
        .map(\.id)
    for folderId in emptyFolderIds {
        pruneWorkspaceFolderIfEmpty(folderId)
    }
    pruneEmptyWorkspaceProjects()
}

@MainActor
func pruneEmptyWorkspaceProjects() {
    // Restored workspaces can be temporarily empty before their windows rebind.
    guard !isRestoringStartupLayout else { return }
    let emptyProjectIds = winMuxWorkspaceState.projectsById.keys.filter { projectId in
        let workspaces = projectWorkspaces(projectId: projectId)
        guard !workspaces.contains(where: workspaceAnchorsEmptySlot) else { return false }
        // A project created in the background must survive until first selected.
        let wasSelected = winMuxWorkspaceState.monitorViewportsById.values.contains {
            $0.lastActiveWorkspaceByProject[projectId] != nil
        }
        if !wasSelected && !workspaces.contains(where: { $0.lifecycle == .durable }) {
            return false
        }
        // Once visited and left, or emptied after use, placeholders do not retain it.
        return !workspaces.contains(where: \.isVisible) || workspaces.contains { $0.lifecycle == .durable }
    }
    for projectId in emptyProjectIds {
        for workspace in projectWorkspaces(projectId: projectId) {
            removeWorkspaceFromRegistry(workspace)
        }
        winMuxWorkspaceState.removeProject(projectId)
        try? clearWorkspaceSidebarProjectMetadata(projectId)
    }
    guard !emptyProjectIds.isEmpty else { return }

    if winMuxWorkspaceState.projectsById.isEmpty {
        _ = createWorkspaceProject(displayName: "Default")
    }
    ensureVisibleActiveProjectWorkspaces()
    if winMuxWorkspaceState.workspaceById[focus.workspace.id] == nil,
       let replacement = mainMonitor.activeWorkspace ?? Workspace.all.first
    {
        _ = setFocus(to: replacement.toLiveFocus())
    }
}

@MainActor
@discardableResult
func pruneWorkspaceFolderIfEmpty(_ folderId: WorkspaceFolderId) -> Bool {
    guard let folder = winMuxWorkspaceState.workspaceFoldersById[folderId],
          let project = winMuxWorkspaceState.projectsById[folder.projectId],
          folderId != project.unfoldedFolderId,
          folder.workspaceOrder.isEmpty,
          !winMuxWorkspaceState.workspaceById.values.contains(where: { $0.folderId == folderId })
    else { return false }

    winMuxWorkspaceState.removeFolder(folderId)
    try? clearWorkspaceSidebarFolderMetadata(folderId)
    return true
}

@MainActor
private func workspaceSidebarProjectHasMetadata(_ projectId: WorkspaceProjectId) -> Bool {
    let rawProjectId = projectId.rawValue
    return config.workspaceSidebar.projectLabels[rawProjectId] != nil ||
        config.workspaceSidebar.projectColors[rawProjectId] != nil
}

@MainActor
private func workspaceTabGroupProjectHasContent(_ projectId: WorkspaceProjectId) -> Bool {
    projectWorkspaces(projectId: projectId).contains {
        !$0.isArchived && (workspaceHasLifecycleWindows($0) || $0.isConfiguredPersistent)
    }
}

@MainActor
func windowsInWorkspaceProject(_ projectId: WorkspaceProjectId) -> [Window] {
    var seen: Set<UInt32> = []
    var result: [Window] = []
    for workspace in Workspace.all where workspace.projectId == projectId {
        for window in workspace.allLeafWindowsRecursive + workspaceOwnedMinimizedWindows(workspace)
        where seen.insert(window.windowId).inserted
        {
            result.append(window)
        }
    }
    return result
}

@MainActor
func windowsInWorkspace(_ workspace: Workspace) -> [Window] {
    var seen: Set<UInt32> = []
    return (workspace.allLeafWindowsRecursive + workspaceOwnedMinimizedWindows(workspace)).filter {
        seen.insert($0.windowId).inserted
    }
}

@MainActor
private func closeWindowsForSidebarDeletion(
    _ windows: [Window],
    terminateAppsWhenAllWindowsIncluded: Bool
) async -> [Window] {
    var remaining: [Window] = []
    let macWindows = windows.compactMap { $0 as? MacWindow }
    let windowsByPid = Dictionary(grouping: macWindows, by: { $0.macApp.pid })
    var handledWindowIds: Set<UInt32> = []

    if terminateAppsWhenAllWindowsIncluded {
        for (_, appWindows) in windowsByPid {
            guard let app = appWindows.first?.macApp else { continue }
            let axWindowCount = (try? await app.getAxWindowsCount()) ?? MacWindow.allWindows.count { $0.macApp === app }
            if axWindowCount == appWindows.count, app.nsApp.terminate() {
                let didTerminate = await waitForAppTermination(app)
                if didTerminate {
                    for window in appWindows {
                        window.garbageCollect(skipClosedWindowsCache: true)
                        handledWindowIds.insert(window.windowId)
                    }
                }
            }
        }
    }

    for window in windows where !handledWindowIds.contains(window.windowId) {
        if let macWindow = window as? MacWindow {
            if await macWindow.requestCloseAndWait() {
                handledWindowIds.insert(window.windowId)
            } else {
                remaining.append(window)
            }
        } else {
            window.closeAxWindow()
            if window.parent == nil {
                handledWindowIds.insert(window.windowId)
            } else {
                remaining.append(window)
            }
        }
    }
    return remaining
}

@MainActor
private func waitForAppTermination(_ app: MacApp, timeout: TimeInterval = 2.0) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if app.nsApp.isTerminated {
            return true
        }
        if (try? await app.getAxWindowsCount()) == 0 {
            return true
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return false
}
