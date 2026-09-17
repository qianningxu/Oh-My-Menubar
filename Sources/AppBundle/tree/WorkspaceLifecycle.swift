import AppKit
import Common

@MainActor
func switchWorkspaceProject(_ projectId: WorkspaceProjectId, on monitor: Monitor) -> Workspace? {
    materializePersistedWorkspaceProjects()
    guard winMuxWorkspaceState.projectsById[projectId] != nil else {
        debugWorkspaceSidebarProjectLog("switchProjectAbort unknownProject=\(projectId.rawValue)")
        return nil
    }
    let viewportId = MonitorViewportId(monitor)
    let preferredWorkspace = availablePreferredWorkspace(projectId: projectId, monitor: monitor)
    let rememberedWorkspace = winMuxWorkspaceState.monitorViewportsById[viewportId]?
        .lastActiveWorkspaceByProject[projectId]
        .flatMap { winMuxWorkspaceState.workspaceById[$0] }
        .flatMap {
            workspaceIsAvailableForMonitor($0, monitor: monitor) &&
                workspaceIsPreferredProjectSwitchTarget($0, preferredWorkspace: preferredWorkspace)
                ? $0
                : nil
        }
    let workspace = rememberedWorkspace
        ?? preferredWorkspace
        ?? createBlankWorkspace(projectId: projectId, monitor: monitor)
    let didSetActive = monitor.setActiveWorkspace(workspace)
    debugWorkspaceSidebarProjectLog(
        "switchProject project=\(projectId.rawValue) viewport=\(viewportId.description) remembered=\(rememberedWorkspace?.name ?? "nil") chosen=\(workspace.name) chosenProject=\(workspace.projectId.rawValue) didSetActive=\(didSetActive)"
    )
    return didSetActive ? workspace : nil
}

@MainActor
func preferredWorkspace(projectId: WorkspaceProjectId, monitor: Monitor) -> Workspace? {
    projectWorkspaces(projectId: projectId)
        .filter { !$0.isArchived }
        .filter { isValidAssignment(workspace: $0, screen: monitor.rect.topLeftCorner) }
        .first
}

@MainActor
func createBlankWorkspace(projectId: WorkspaceProjectId, monitor: Monitor) -> Workspace {
    winMuxWorkspaceState.ensureProjectExists(projectId)
    return createBlankWorkspace(folderId: winMuxWorkspaceState.unfoldedFolderId(for: projectId), monitor: monitor)
}

@MainActor
func createBlankWorkspace(folderId: WorkspaceFolderId, monitor: Monitor) -> Workspace {
    winMuxWorkspaceState.ensureFolderExists(folderId)
    let projectId = winMuxWorkspaceState.workspaceFoldersById[folderId]?.projectId ?? workspaceProjectDefaultId
    let workspace = Workspace.get(byName: nextAutomaticWorkspaceName(projectId: projectId, monitor: monitor))
    workspace.markAsTransientBlank()
    workspace.assignFolder(folderId)
    workspace.seedMonitorIfNeeded(monitor)
    return workspace
}

@MainActor
func createFreshAdjacentBlankWorkspace(projectId: WorkspaceProjectId, monitor: Monitor, after anchor: Workspace?) -> Workspace {
    let workspace = createBlankWorkspace(projectId: projectId, monitor: monitor)
    if let anchor {
        _ = winMuxWorkspaceState.reorderWorkspace(workspace.id, inFolder: workspace.folderId, destination: .after(anchor.id))
    }
    return workspace
}

@MainActor
func createFreshAdjacentBlankWorkspace(folderId: WorkspaceFolderId, monitor: Monitor, after anchor: Workspace?) -> Workspace {
    let workspace = createBlankWorkspace(folderId: folderId, monitor: monitor)
    if let anchor, anchor.folderId == folderId {
        _ = winMuxWorkspaceState.reorderWorkspace(workspace.id, inFolder: folderId, destination: .after(anchor.id))
    }
    return workspace
}

@MainActor
func getOrCreateAdjacentBlankWorkspace(projectId: WorkspaceProjectId, monitor: Monitor) -> Workspace {
    let scope = WorkspaceScope(projectId: projectId, monitor: monitor)
    if let workspaceId = retainedEmptyWorkspaceId(in: scope),
       let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
       workspaceIsAvailableForMonitor(workspace, monitor: monitor)
    {
        return workspace
    }
    return createBlankWorkspace(projectId: projectId, monitor: monitor)
}

@MainActor
func deleteWorkspace(_ workspace: Workspace) throws {
    let fallback = workspaceFallbackForDeletion(
        excluding: workspace,
        projectId: workspace.projectId,
        monitor: workspace.workspaceMonitor,
    )
    moveWorkspaceContents(from: workspace, to: fallback)
    if workspace.isVisible {
        check(
            workspace.workspaceMonitor.setActiveWorkspace(fallback),
            "Can't activate fallback workspace '\(fallback.name)' while deleting workspace '\(workspace.name)'",
        )
    }
    if focus.workspace == workspace {
        _ = setFocus(to: fallback.toLiveFocus())
    }
    removeWorkspaceFromRegistry(workspace)
    checkWorkspaceHierarchyInvariants()
}

@MainActor
func workspaceFallbackForDeletion(
    excluding workspace: Workspace,
    projectId: WorkspaceProjectId,
    monitor: Monitor,
) -> Workspace {
    closestWorkspaceForDeletion(
        excluding: workspace,
        projectId: projectId,
        monitor: monitor,
    )
        ?? createBlankWorkspace(projectId: projectId, monitor: monitor)
}

@MainActor
func closestWorkspaceForDeletion(
    excluding workspace: Workspace,
    projectId: WorkspaceProjectId,
    monitor: Monitor,
) -> Workspace? {
    let scopedCandidates = userFacingWorkspaces(
        orderedWorkspaces(in: projectId),
        focusedWorkspace: focus.workspace,
    )
        .filter { isValidAssignment(workspace: $0, screen: monitor.rect.topLeftCorner) }
    let automaticCandidates = scopedCandidates.filter(\.usesAutomaticDisplayName)
    let candidates = workspace.usesAutomaticDisplayName && automaticCandidates.contains(workspace)
        ? automaticCandidates
        : scopedCandidates

    guard let deletedIndex = candidates.firstIndex(where: { $0 === workspace }) else {
        return candidates.first { $0 !== workspace }
    }
    if deletedIndex > 0 {
        return candidates[deletedIndex - 1]
    }
    return candidates.getOrNil(atIndex: deletedIndex + 1)
}

@MainActor
private func adjacentWorkspaceForPrunedWorkspace(
    _ workspace: Workspace,
    orderedWorkspaces: [Workspace],
    isEligible: (Workspace) -> Bool,
) -> Workspace? {
    guard let workspaceIndex = orderedWorkspaces.firstIndex(where: { $0 === workspace }) else {
        return orderedWorkspaces.first(where: isEligible)
    }
    if workspaceIndex > 0,
       let workspaceAbove = orderedWorkspaces[..<workspaceIndex].reversed().first(where: isEligible)
    {
        return workspaceAbove
    }
    return orderedWorkspaces.dropFirst(workspaceIndex + 1).first(where: isEligible)
}

@MainActor
func moveWorkspaceContents(from source: Workspace, to target: Workspace) {
    guard source != target else { return }
    for child in source.children {
        switch child.nodeCases {
            case .window(let window):
                window.bind(to: target, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            case .tilingContainer(let container):
                container.bind(to: target.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            case .macosFullscreenWindowsContainer(let container):
                for window in container.children.filterIsInstance(of: Window.self) {
                    window.bind(to: target.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                }
            case .macosHiddenAppsWindowsContainer(let container):
                for window in container.children.filterIsInstance(of: Window.self) {
                    window.bind(to: target.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                }
            case .workspace, .macosMinimizedWindowsContainer, .macosPopupWindowsContainer:
                break
        }
    }
    for window in workspaceOwnedMinimizedWindows(source) {
        switch window.layoutReason {
            case .macos(let prevParentKind, _):
                window.layoutReason = .macos(prevParentKind: prevParentKind, prevWorkspaceName: target.name)
            case .standard:
                break
        }
    }
}

@MainActor
func removeWorkspaceFromRegistry(
    _ workspace: Workspace,
    clearsSidebarLabel: Bool = true
) {
    if clearsSidebarLabel {
        clearWorkspaceSidebarLabelIfNeeded(workspace.name)
    }
    _ = winMuxWorkspaceState.removeWorkspace(workspace)
}

@MainActor
func workspaceToCloseAfterClosingLastWindow(_ window: Window) -> Workspace? {
    guard let workspace = lifecycleWorkspace(for: window), !workspace.isConfiguredPersistent else {
        return nil
    }
    let windows = lifecycleWindows(in: workspace)
    return windows.count == 1 && windows.singleOrNil() === window ? workspace : nil
}

@MainActor
private func lifecycleWorkspace(for window: Window) -> Workspace? {
    if let workspace = window.nodeWorkspace {
        return workspace
    }
    if case .macos(_, let prevWorkspaceName) = window.layoutReason {
        return prevWorkspaceName.flatMap(Workspace.existing(byName:))
    }
    return nil
}

@MainActor
private func lifecycleWindows(in workspace: Workspace) -> [Window] {
    var seenWindowIds: Set<UInt32> = []
    return (workspace.allLeafWindowsRecursive + workspaceOwnedMinimizedWindows(workspace)).filter {
        seenWindowIds.insert($0.windowId).inserted
    }
}

@MainActor
func closeWorkspaceIfEmptiedByLastWindowClosure(_ workspace: Workspace?) {
    guard let workspace,
          winMuxWorkspaceState.workspaceById[workspace.id] === workspace,
          !workspace.isConfiguredPersistent,
          !workspaceHasLifecycleWindows(workspace)
    else {
        return
    }

    let isLastWorkspaceInProject = projectWorkspaces(projectId: workspace.projectId)
        .filter { $0 !== workspace }
        .allSatisfy { !workspaceAnchorsEmptySlot($0) }
    let replacement: Workspace?
    if isLastWorkspaceInProject {
        let fallbackProjectId = workspaceProjectFallbackForDeletion(excluding: workspace.projectId)
        replacement = getOrCreateFallbackWorkspace(
            projectId: fallbackProjectId,
            monitor: workspace.workspaceMonitor,
            excluding: workspace,
            excludingIds: [workspace.id]
        )
    } else {
        let retainedEmptyWorkspaceIds = retainedEmptyWorkspaceIdsByScope()
        replacement = replacementWorkspaceForPrunedWorkspace(
            workspace,
            retainedEmptyWorkspaceIds: retainedEmptyWorkspaceIds,
            excludingWorkspaceIds: [workspace.id]
        )
    }
    if workspace.isVisible, let replacement {
        check(
            workspace.workspaceMonitor.setActiveWorkspace(replacement),
            "Can't replace closed empty workspace '\(workspace.name)' with '\(replacement.name)'",
        )
    }
    if focus.workspace == workspace {
        let focusReplacement = replacement ?? focusReplacementForPrunedWorkspace(workspace)
        if let focusReplacement {
            _ = setFocus(to: focusReplacement.toLiveFocus())
        }
    }
    removeWorkspaceFromRegistry(workspace)
    if isLastWorkspaceInProject {
        for placeholder in projectWorkspaces(projectId: workspace.projectId) {
            removeWorkspaceFromRegistry(placeholder)
        }
    }
    pruneEmptyWorkspaceTabGroups()
    checkWorkspaceHierarchyInvariants()
}

@MainActor
func pruneEmptyWorkspaces() {
    let retainedEmptyWorkspaceIds = retainedEmptyWorkspaceIdsByScope()
    let focusedWorkspaceBeforePrune = focus.workspace
    let workspacesToRemove = Workspace.all.filter {
        !workspaceShouldSurviveReconciliation($0, retainedEmptyWorkspaceIds: retainedEmptyWorkspaceIds)
    }
    let workspaceIdsToRemove = Set(workspacesToRemove.map(\.id))
    var focusedReplacement: Workspace?

    for workspace in workspacesToRemove {
        let replacement = replacementWorkspaceForPrunedWorkspace(
            workspace,
            retainedEmptyWorkspaceIds: retainedEmptyWorkspaceIds,
            excludingWorkspaceIds: workspaceIdsToRemove,
        )
        if workspace.isVisible, let replacement {
            check(
                workspace.workspaceMonitor.setActiveWorkspace(replacement),
                "Can't replace pruned empty workspace '\(workspace.name)' with '\(replacement.name)'",
            )
        }
        if workspace == focusedWorkspaceBeforePrune {
            focusedReplacement = replacement ?? focusReplacementForPrunedWorkspace(workspace)
        }
        // Reconciliation can see a restored workspace before its windows have
        // rebound. Preserve its persisted label so the later restoration of a
        // workspace with the same stable name can reuse it.
        removeWorkspaceFromRegistry(workspace, clearsSidebarLabel: false)
    }

    if let focusedReplacement, focus.workspace != focusedReplacement {
        _ = setFocus(to: focusedReplacement.toLiveFocus())
    }
}

@MainActor
func focusReplacementForPrunedWorkspace(_ workspace: Workspace) -> Workspace? {
    focusReplacementForPrunedWorkspace(workspace, excludingWorkspaceIds: [workspace.id])
}

@MainActor
func focusReplacementForPrunedWorkspace(_ workspace: Workspace, excludingWorkspaceIds: Set<WorkspaceId>) -> Workspace? {
    let visibleWorkspaces = Workspace.all.filter {
        $0.isVisible && $0 != workspace && !excludingWorkspaceIds.contains($0.id)
    }
    if let mainVisible = visibleWorkspaces.first(where: { $0 === mainMonitor.activeWorkspace }) {
        return mainVisible
    }
    return visibleWorkspaces.first { $0.projectId == workspace.projectId } ?? visibleWorkspaces.first
}

@MainActor
func workspaceShouldSurviveReconciliation(
    _ workspace: Workspace,
    retainedEmptyWorkspaceIds: [WorkspaceScope: WorkspaceId],
) -> Bool {
    guard !workspace.isArchived else { return false }
    let scope = WorkspaceScope(projectId: workspace.projectId, monitor: workspace.workspaceMonitor)
    let isReplaceableVisibleRename = workspace.isVisible &&
        workspace.isOrdinaryEmptySlot &&
        workspaceHasSidebarDisplayNameOverride(workspace.name)
    return (workspace.isVisible && !isReplaceableVisibleRename && shouldRetainVisibleWorkspaceDuringPrune(workspace)) ||
        workspaceHasLifecycleWindows(workspace) ||
        workspace.isConfiguredPersistent ||
        (!isReplaceableVisibleRename && shouldRetainLastEmptyWorkspaceInProject(workspace)) ||
        retainedEmptyWorkspaceIds[scope] == workspace.id
}

@MainActor
private func shouldRetainVisibleWorkspaceDuringPrune(_ workspace: Workspace) -> Bool {
    true
}

@MainActor
private func shouldRetainLastEmptyWorkspaceInProject(_ workspace: Workspace) -> Bool {
    guard projectWorkspaces(projectId: workspace.projectId).filter({ !$0.isArchived }).count == 1 else {
        return false
    }
    return true
}

@MainActor
func replacementWorkspaceForPrunedWorkspace(
    _ workspace: Workspace,
    retainedEmptyWorkspaceIds: [WorkspaceScope: WorkspaceId],
    excludingWorkspaceIds: Set<WorkspaceId> = [],
) -> Workspace? {
    let scope = WorkspaceScope(projectId: workspace.projectId, monitor: workspace.workspaceMonitor)
    let isReplaceableVisibleRename = workspace.isVisible &&
        workspace.isOrdinaryEmptySlot &&
        workspaceHasSidebarDisplayNameOverride(workspace.name)
    let orderedScopeWorkspaces = orderedWorkspaces(in: scope)
    if let candidate = adjacentWorkspaceForPrunedWorkspace(
        workspace,
        orderedWorkspaces: orderedScopeWorkspaces,
        isEligible: {
            $0.id != workspace.id &&
                !excludingWorkspaceIds.contains($0.id) &&
                workspaceShouldSurviveReconciliation($0, retainedEmptyWorkspaceIds: retainedEmptyWorkspaceIds) &&
                isUserFacingWorkspace($0) &&
                workspaceIsAvailableForMonitor($0, monitor: workspace.workspaceMonitor)
        }
    ) {
        return candidate
    }
    if !isReplaceableVisibleRename,
       let retainedWorkspaceId = retainedEmptyWorkspaceIds[scope],
       retainedWorkspaceId != workspace.id,
       let retainedWorkspace = winMuxWorkspaceState.workspaceById[retainedWorkspaceId],
       !excludingWorkspaceIds.contains(retainedWorkspace.id),
       workspaceIsAvailableForMonitor(retainedWorkspace, monitor: workspace.workspaceMonitor)
    {
        return retainedWorkspace
    }
    if workspace.isVisible {
        let fallbackProjectId = (!projectsAreEnabled() && workspace.projectId != workspaceProjectDefaultId)
            ? workspaceProjectDefaultId
            : workspace.projectId
        return getOrCreateFallbackWorkspace(
            projectId: fallbackProjectId,
            monitor: workspace.workspaceMonitor,
            excluding: workspace,
            excludingIds: excludingWorkspaceIds,
        )
    }
    return nil
}

@MainActor
func ensureVisibleActiveProjectWorkspaces() {
    for monitor in monitors where winMuxWorkspaceState.visibleWorkspace(for: monitor) == nil {
        let viewportId = MonitorViewportId(monitor)
        let projectId = fallbackProjectIdForMissingActiveWorkspace(on: viewportId)
        let workspace = availablePreferredWorkspace(projectId: projectId, monitor: monitor)
            ?? createBlankWorkspace(projectId: projectId, monitor: monitor)
        check(monitor.setActiveWorkspace(workspace))
    }
}

@MainActor
private func fallbackProjectIdForMissingActiveWorkspace(on viewportId: MonitorViewportId) -> WorkspaceProjectId {
    let viewport = winMuxWorkspaceState.monitorViewportsById[viewportId]
    if let previousProjectId = viewport?.previousWorkspaceId.flatMap({ winMuxWorkspaceState.workspaceById[$0]?.projectId }) {
        return previousProjectId
    }
    if let rememberedProjectId = viewport?.lastActiveWorkspaceByProject
        .sorted(by: { $0.key < $1.key })
        .first(where: { entry in winMuxWorkspaceState.workspaceById[entry.value] != nil })?
        .key
    {
        return rememberedProjectId
    }
    return winMuxWorkspaceState.projectsById[workspaceProjectDefaultId].map { _ in workspaceProjectDefaultId }
        ?? workspaceProjects().first?.id
        ?? createWorkspaceProject(displayName: "Default").id
}

@MainActor
func availablePreferredWorkspace(projectId: WorkspaceProjectId, monitor: Monitor) -> Workspace? {
    let candidates = orderedWorkspacesForPresentation()
        .filter { $0.projectId == projectId }
        .filter { !$0.isArchived }
        .filter { isValidAssignment(workspace: $0, screen: monitor.rect.topLeftCorner) }
        .filter { workspaceIsAvailableForMonitor($0, monitor: monitor) }
    return candidates.first(where: workspaceIsPreferredProjectSwitchContent) ?? candidates.first
}

@MainActor
func workspaceIsAvailableForMonitor(_ workspace: Workspace, monitor: Monitor) -> Bool {
    isValidAssignment(workspace: workspace, screen: monitor.rect.topLeftCorner) &&
        (!workspace.isVisible || workspace.workspaceMonitor.rect.topLeftCorner == monitor.rect.topLeftCorner)
}

@MainActor
private func workspaceIsPreferredProjectSwitchTarget(
    _ workspace: Workspace,
    preferredWorkspace: Workspace?
) -> Bool {
    workspaceIsPreferredProjectSwitchContent(workspace) || preferredWorkspace == nil || preferredWorkspace == workspace
}

@MainActor
private func workspaceIsPreferredProjectSwitchContent(_ workspace: Workspace) -> Bool {
    workspaceHasSidebarVisibleWindows(workspace) ||
        workspace.isConfiguredPersistent ||
        !workspaceOwnedMinimizedWindows(workspace).isEmpty
}

@MainActor
func repairInvalidVisibleWorkspaceAssignments() {
    let invalidVisibleWorkspaces = winMuxWorkspaceState.monitorViewportsById.compactMap { viewportId, viewport -> Workspace? in
        guard let workspaceId = viewport.activeWorkspaceId,
              let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
              !isValidAssignment(workspace: workspace, screen: viewportId.topLeftCorner)
        else {
            return nil
        }
        return workspace
    }

    for workspace in invalidVisibleWorkspaces {
        if let forceAssignedMonitor = workspace.forceAssignedMonitor {
            _ = activateWorkspaceOnMonitorPreservingSourceViewport(workspace, targetMonitor: forceAssignedMonitor)
        }
    }

    for (viewportId, viewport) in winMuxWorkspaceState.monitorViewportsById {
        guard let workspaceId = viewport.activeWorkspaceId,
              let workspace = winMuxWorkspaceState.workspaceById[workspaceId],
              !isValidAssignment(workspace: workspace, screen: viewportId.topLeftCorner)
        else {
            continue
        }
        var viewport = viewport
        viewport.activeWorkspaceId = nil
        if viewport.previousWorkspaceId == workspaceId {
            viewport.previousWorkspaceId = nil
        }
        winMuxWorkspaceState.monitorViewportsById[viewportId] = viewport
    }
}
