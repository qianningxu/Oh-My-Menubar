import AppKit
import Common
import SwiftUI

enum WorkspaceSidebarPostRefreshPolicy: Equatable, Sendable {
    case none
    case reconcileNativeWindowInventory

    var shouldSchedulePostRefresh: Bool {
        self == .reconcileNativeWindowInventory
    }
}

func workspaceSidebarProjectDeletionPostRefreshPolicy(
    for action: WorkspaceProjectDeletionAction
) -> WorkspaceSidebarPostRefreshPolicy {
    switch action {
        case .closeWindows:
            .reconcileNativeWindowInventory
        case .moveWindowsToFallback:
            .none
    }
}

@MainActor
func focusWorkspaceFromSidebar(_ workspaceName: String, targetMonitorScopeId: String? = nil) {
    WorkspaceSidebarPanel.suppressEdgeTrapForWorkspaceActivation()
    runWorkspaceSidebarSession(prioritizeFocusSync: true) {
        guard let workspace = Workspace.existing(byName: workspaceName) else { return }
        _ = focusWorkspaceFromSidebar(workspace, targetMonitorScopeId: targetMonitorScopeId)
    }
}

@MainActor
func focusWorkspaceFromSidebar(_ workspace: Workspace, targetMonitorScopeId: String? = nil) -> Bool {
    guard let targetMonitorScopeId,
          let targetMonitor = workspaceSidebarMonitor(forScopeId: targetMonitorScopeId)
    else {
        return workspace.focusWorkspace()
    }

    if workspace.isVisible {
        guard workspace.workspaceMonitor.rect.topLeftCorner == targetMonitor.rect.topLeftCorner else {
            return false
        }
        return workspace.focusWorkspace()
    }

    guard targetMonitor.setActiveWorkspace(workspace) else { return false }
    return workspace.focusWorkspace()
}

@MainActor
func overrideWorkspaceInUseFromSidebar(_ workspaceName: String, targetMonitorScopeId: String? = nil) {
    WorkspaceSidebarPanel.suppressEdgeTrapForWorkspaceActivation()
    runWorkspaceSidebarSession(prioritizeFocusSync: true) {
        guard let workspace = Workspace.existing(byName: workspaceName),
              let targetMonitorScopeId,
              let targetMonitor = workspaceSidebarMonitor(forScopeId: targetMonitorScopeId)
        else { return }
        _ = overrideWorkspaceOnMonitorBySwappingActiveViewports(workspace, targetMonitor: targetMonitor)
        _ = workspace.focusWorkspace()
    }
}

@MainActor
@discardableResult
func runWorkspaceSidebarSession(
    postRefresh: WorkspaceSidebarPostRefreshPolicy = .none,
    prioritizeFocusSync: Bool = false,
    _ body: @escaping @MainActor () async throws -> Void
) -> Task<Void, Never>? {
    guard let token: RunSessionGuard = .isServerEnabled else { return nil }
    return Task { @MainActor in
        do {
            try await runLightSession(
                .menuBarButton,
                token,
                shouldSchedulePostRefresh: postRefresh.shouldSchedulePostRefresh,
                prioritizeFocusSync: prioritizeFocusSync
            ) {
                try await body()
            }
            persistSidebarStateForRestartIfPossible()
        } catch {
            showWorkspaceSidebarError(error.localizedDescription)
        }
    }
}

@MainActor
func runWorkspaceSidebarPostMutationSession() {
    runWorkspaceSidebarSession {}
}

@MainActor
func showWorkspaceSidebarError(_ body: String) {
    MessageModel.shared.message = Message(
        description: "Tab Sidebar Error",
        body: body,
    )
}

@MainActor
func setWorkspaceSidebarAutoHide(
    _ isEnabled: Bool,
    viewModel: TrayMenuModel = TrayMenuModel.shared,
) {
    guard workspaceSidebarAutoHidePreference() != isEnabled else { return }
    setWorkspaceSidebarAutoHidePreference(isEnabled)
    viewModel.isWorkspaceSidebarAutoHideEnabled = isEnabled
    viewModel.isWorkspaceSidebarPinnedExpanded = !isEnabled
    for panel in WorkspaceSidebarPanel.allPanels {
        panel.viewModel.isWorkspaceSidebarAutoHideEnabled = isEnabled
        panel.viewModel.isWorkspaceSidebarPinnedExpanded = !isEnabled
    }
    WorkspaceSidebarPanel.refreshAll()
    scheduleRefreshSession(.workspaceSidebarWidthChanged)
}

@MainActor
func setWorkspaceSidebarPinnedExpanded(
    _ isPinned: Bool,
    viewModel: TrayMenuModel = TrayMenuModel.shared,
) {
    setWorkspaceSidebarAutoHide(!isPinned, viewModel: viewModel)
}

@MainActor
func sidebarWorkspaceTargetMonitor(fallbackWindow: Window? = nil, fallbackPoint: CGPoint? = nil) -> Monitor {
    workspaceSidebarTargetMonitor(
        selectedMonitor: selectedWorkspaceSidebarMonitorScope(),
        fallbackPoint: fallbackPoint,
        fallbackWindowMonitor: fallbackWindow?.nodeMonitor,
        focusedMonitor: focus.workspace.workspaceMonitor,
    )
}

@MainActor
func workspaceSidebarTargetMonitor(
    selectedMonitor: Monitor?,
    fallbackPoint: CGPoint?,
    fallbackWindowMonitor: Monitor?,
    focusedMonitor: Monitor,
) -> Monitor {
    selectedMonitor ??
        fallbackPoint?.monitorApproximation ??
        fallbackWindowMonitor ??
        focusedMonitor
}

@MainActor
func selectedWorkspaceSidebarMonitorScope() -> Monitor? {
    let selectedScopeId = TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId
    guard selectedScopeId != workspaceSidebarDefaultScopeId,
          selectedScopeId != workspaceSidebarFocusedScopeId
    else {
        return nil
    }
    return sortedMonitors.first { workspaceSidebarMonitorScopeId(for: $0) == selectedScopeId }
}

@MainActor
func workspaceSidebarTargetMonitor(
    scopeId: String,
    fallbackWindow: Window? = nil,
    fallbackPoint: CGPoint? = nil,
) -> Monitor {
    let selectedMonitor = workspaceSidebarMonitorForScopeId(scopeId)
    return workspaceSidebarTargetMonitor(
        selectedMonitor: selectedMonitor,
        fallbackPoint: fallbackPoint,
        fallbackWindowMonitor: fallbackWindow?.nodeMonitor,
        focusedMonitor: focus.workspace.workspaceMonitor,
    )
}

@MainActor
private func workspaceSidebarMonitorForScopeId(_ scopeId: String) -> Monitor? {
    guard scopeId != workspaceSidebarDefaultScopeId,
          scopeId != workspaceSidebarFocusedScopeId
    else {
        return nil
    }
    return sortedMonitors.first { workspaceSidebarMonitorScopeId(for: $0) == scopeId }
}

func workspaceSidebarWorkspaceCreateScope(
    selectedScopeId: String,
    targetMonitorScopeId: String,
    focusedScopeId: String,
) -> String {
    switch selectedScopeId {
        case workspaceSidebarDefaultScopeId:
            targetMonitorScopeId
        case workspaceSidebarFocusedScopeId:
            focusedScopeId
        default:
            selectedScopeId
    }
}

@MainActor
func selectWorkspaceSidebarMonitorScope(_ scopeId: String, viewModel: TrayMenuModel = TrayMenuModel.shared) {
    guard viewModel.workspaceSidebarMonitorScopes.contains(where: { $0.id == scopeId }) else { return }
    guard viewModel.workspaceSidebarSelectedMonitorScopeId != scopeId else { return }
    viewModel.workspaceSidebarSelectedMonitorScopeId = scopeId
    let visibleWorkspaceNames = Set(viewModel.visibleWorkspaceSidebarWorkspaces.map(\.name))
    let sanitizedHoveredWorkspaceName = sanitizedWorkspaceSidebarHoveredWorkspaceName(
        visibleWorkspaceNames: visibleWorkspaceNames,
        hoveredWorkspaceName: viewModel.workspaceSidebarHoveredWorkspaceName,
    )
    if viewModel.workspaceSidebarHoveredWorkspaceName != sanitizedHoveredWorkspaceName {
        viewModel.workspaceSidebarHoveredWorkspaceName = sanitizedHoveredWorkspaceName
    }
}

@MainActor
func createWorkspaceFromSidebarButton() {
    let targetMonitor = sidebarWorkspaceTargetMonitor()
    createWorkspaceFromSidebarButton(
        projectId: activeWorkspaceProjectId(for: targetMonitor),
        monitorScopeId: TrayMenuModel.shared.workspaceSidebarSelectedMonitorScopeId,
    )
}

@MainActor
func createWorkspaceFromSidebarButton(projectId: WorkspaceProjectId, monitorScopeId: String) {
    runWorkspaceSidebarSession {
        let targetMonitor = workspaceSidebarTargetMonitor(scopeId: monitorScopeId)
        let activeWorkspace = targetMonitor.activeWorkspace
        let folderId = activeWorkspace.projectId == projectId
            ? activeWorkspace.folderId
            : winMuxWorkspaceState.unfoldedFolderId(for: projectId)
        let workspace = createFreshAdjacentBlankWorkspace(
            folderId: folderId,
            monitor: targetMonitor,
            after: activeWorkspace
        )
        _ = workspace.focusWorkspace()
    }
}

@MainActor
func closeWindowFromSidebar(_ windowId: UInt32) {
    runWorkspaceSidebarSession(postRefresh: .reconcileNativeWindowInventory) {
        var args = CloseCmdArgs(rawArgs: [])
        args.windowId = windowId
        _ = try await CloseCommand(args: args).run(.defaultEnv, .emptyStdin)
    }
}

@MainActor
func createWorkspaceFromSidebarDrag(sourceNode: TreeNode, sourceWindow: Window) -> Bool {
    createWorkspaceFromSidebarDrag(sourceNode: sourceNode, sourceWindow: sourceWindow, projectId: nil, monitorScopeId: nil)
}

@MainActor
func createWorkspaceFromSidebarDrag(
    sourceNode: TreeNode,
    sourceWindow: Window,
    projectId: WorkspaceProjectId?,
    monitorScopeId: String?,
) -> Bool {
    let targetMonitor = monitorScopeId.map {
        workspaceSidebarTargetMonitor(
            scopeId: $0,
            fallbackWindow: sourceWindow,
            fallbackPoint: mouseLocation,
        )
    } ?? sidebarWorkspaceTargetMonitor(fallbackWindow: sourceWindow, fallbackPoint: mouseLocation)
    let projectId = projectId ?? activeWorkspaceProjectId(for: targetMonitor)
    let workspace = getOrCreateAdjacentBlankWorkspace(projectId: projectId, monitor: targetMonitor)
    let targetContainer: NonLeafTreeNodeObject
    if sourceNode is Window, sourceWindow.isFloating {
        targetContainer = workspace
    } else {
        targetContainer = workspace.rootTilingContainer
    }
    sourceNode.bind(to: targetContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    setWorkspaceSidebarFolderExpanded(workspace.folderId, isExpanded: true)
    return true
}

@MainActor
func moveWindowFromSidebar(_ windowId: UInt32, toWorkspace workspaceName: String) {
    moveSidebarSource(windowId, subject: .window, toWorkspace: workspaceName)
}

@MainActor
func moveTabGroupFromSidebar(_ windowId: UInt32, toWorkspace workspaceName: String) {
    moveSidebarSource(windowId, subject: .group, toWorkspace: workspaceName)
}

@MainActor
func moveWindowToNewWorkspaceFromSidebar(_ windowId: UInt32, projectId: WorkspaceProjectId, monitorScopeId: String) {
    moveSidebarSourceToNewWorkspace(windowId, subject: .window, projectId: projectId, monitorScopeId: monitorScopeId)
}

@MainActor
func moveTabGroupToNewWorkspaceFromSidebar(_ windowId: UInt32, projectId: WorkspaceProjectId, monitorScopeId: String) {
    moveSidebarSourceToNewWorkspace(windowId, subject: .group, projectId: projectId, monitorScopeId: monitorScopeId)
}

@MainActor
func moveWindowToNewWorkspaceInFolderFromSidebar(_ windowId: UInt32, folderId: WorkspaceFolderId, monitorScopeId: String) {
    moveSidebarSourceToNewWorkspace(windowId, subject: .window, folderId: folderId, monitorScopeId: monitorScopeId)
}

@MainActor
func moveTabGroupToNewWorkspaceInFolderFromSidebar(_ windowId: UInt32, folderId: WorkspaceFolderId, monitorScopeId: String) {
    moveSidebarSourceToNewWorkspace(windowId, subject: .group, folderId: folderId, monitorScopeId: monitorScopeId)
}

@MainActor
private func moveSidebarSource(_ windowId: UInt32, subject: WindowDragSubject, toWorkspace workspaceName: String) {
    runWorkspaceSidebarSession {
        guard applySidebarSource(windowId, subject: subject, toWorkspace: workspaceName) else { return }
    }
}

@MainActor
private func moveSidebarSourceToNewWorkspace(
    _ windowId: UInt32,
    subject: WindowDragSubject,
    projectId: WorkspaceProjectId,
    monitorScopeId: String,
) {
    let folderId = winMuxWorkspaceState.unfoldedFolderId(for: projectId)
    moveSidebarSourceToNewWorkspace(
        windowId,
        subject: subject,
        folderId: folderId,
        monitorScopeId: monitorScopeId
    )
}

@MainActor
private func moveSidebarSourceToNewWorkspace(
    _ windowId: UInt32,
    subject: WindowDragSubject,
    folderId: WorkspaceFolderId,
    monitorScopeId: String,
) {
    runWorkspaceSidebarSession {
        guard applySidebarSourceToNewWorkspace(
            windowId,
            subject: subject,
            folderId: folderId,
            monitorScopeId: monitorScopeId
        ) else { return }
    }
}

@MainActor
private func applySidebarSource(_ windowId: UInt32, subject: WindowDragSubject, toWorkspace workspaceName: String) -> Bool {
    guard let sourceWindow = Window.get(byId: windowId),
          let targetWorkspace = Workspace.existing(byName: workspaceName)
    else { return false }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    syncClosedWindowsCacheToCurrentWorld()
    suppressPostDragAxObserverEvents(for: sourceNode.allLeafWindowsRecursive.map(\.windowId))
    applySidebarWorkspaceMove(sourceNode: sourceNode, sourceWindow: sourceWindow, targetWorkspace: targetWorkspace)
    return true
}

@MainActor
private func applySidebarSourceToNewWorkspace(
    _ windowId: UInt32,
    subject: WindowDragSubject,
    projectId: WorkspaceProjectId,
    monitorScopeId: String,
) -> Bool {
    applySidebarSourceToNewWorkspace(
        windowId,
        subject: subject,
        folderId: winMuxWorkspaceState.unfoldedFolderId(for: projectId),
        monitorScopeId: monitorScopeId
    )
}

@MainActor
func applySidebarSourceToNewWorkspace(
    _ windowId: UInt32,
    subject: WindowDragSubject,
    folderId: WorkspaceFolderId,
    monitorScopeId: String,
) -> Bool {
    guard let sourceWindow = Window.get(byId: windowId) else { return false }
    guard winMuxWorkspaceState.workspaceFoldersById[folderId] != nil else { return false }
    let sourceNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let targetMonitor = workspaceSidebarTargetMonitor(
        scopeId: monitorScopeId,
        fallbackWindow: sourceWindow,
        fallbackPoint: mouseLocation,
    )
    let workspace = createBlankWorkspace(folderId: folderId, monitor: targetMonitor)
    let targetContainer: NonLeafTreeNodeObject = sourceNode is Window && sourceWindow.isFloating
        ? workspace
        : workspace.rootTilingContainer
    syncClosedWindowsCacheToCurrentWorld()
    suppressPostDragAxObserverEvents(for: sourceNode.allLeafWindowsRecursive.map(\.windowId))
    sourceNode.bind(to: targetContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    setWorkspaceSidebarFolderExpanded(folderId, isExpanded: true)
    return true
}

@MainActor
func previewWorkspaceSidebarDrop(_ windowId: UInt32, subject: WindowDragSubject, target: WorkspaceSidebarDropTargetKind) {
    guard let sourceWindow = Window.get(byId: windowId) else {
        clearWorkspaceSidebarDropPreview()
        return
    }
    guard isActionableSidebarDropTarget(sourceWindow: sourceWindow, subject: subject, target: target) else {
        clearWorkspaceSidebarDropPreview()
        return
    }
    guard case .workspace(let workspaceName) = target else {
        if case .newWorkspace(let projectId, let monitorScopeId) = target {
            setWorkspaceSidebarDropPreviewIfChanged(workspaceSidebarDropPreview(
                sourceWindow: sourceWindow,
                subject: subject,
                targetWorkspaceName: nil,
                targetsNewWorkspace: true,
                targetProjectId: projectId,
                targetMonitorScopeId: monitorScopeId,
            ))
        } else if case .folder(let projectId, let monitorScopeId) = target {
            setWorkspaceSidebarDropPreviewIfChanged(workspaceSidebarDropPreview(
                sourceWindow: sourceWindow,
                subject: subject,
                targetWorkspaceName: nil,
                targetsNewWorkspace: false,
                targetProjectId: projectId,
                targetMonitorScopeId: monitorScopeId,
            ))
        } else {
            clearWorkspaceSidebarDropPreview()
        }
        return
    }
    setWorkspaceSidebarDropPreviewIfChanged(workspaceSidebarDropPreview(
        sourceWindow: sourceWindow,
        subject: subject,
        targetWorkspaceName: workspaceName,
        targetsNewWorkspace: false,
        targetProjectId: nil,
    ))
}

@MainActor
func clearWorkspaceSidebarDropPreview() {
    var transaction = Transaction()
    transaction.animation = nil
    withTransaction(transaction) {
        setWorkspaceSidebarDropPreviewIfChanged(nil)
    }
}

@MainActor
func workspaceSidebarSourcePreview(sourceWindow: Window, subject: WindowDragSubject) -> WorkspaceSidebarDropPreviewViewModel {
    workspaceSidebarDropPreview(
        sourceWindow: sourceWindow,
        subject: subject,
        targetWorkspaceName: nil,
        targetsNewWorkspace: false,
    )
}

@MainActor
func showWorkspaceSidebarDragCursorPreview(sourceWindow: Window, subject: WindowDragSubject, point: CGPoint) {
    WindowDragCursorProxyPanel.shared.show(
        preview: workspaceSidebarSourcePreview(sourceWindow: sourceWindow, subject: subject),
        mouseScreenPoint: denormalizedAppKitScreenPoint(point),
    )
}

func denormalizedAppKitScreenPoint(_ point: CGPoint) -> CGPoint {
    normalizeAppKitScreenPoint(point)
}

@MainActor
private func isActionableSidebarDropTarget(
    sourceWindow: Window,
    subject: WindowDragSubject,
    target: WorkspaceSidebarDropTargetKind,
) -> Bool {
    let sourceWorkspaceName = dragSubjectNode(for: sourceWindow, subject: subject).nodeWorkspace?.name
    return isActionableSidebarWorkspaceDropTarget(sourceWorkspaceName: sourceWorkspaceName, targetKind: target)
}

@MainActor
private func workspaceSidebarDropPreview(
    sourceWindow: Window,
    subject: WindowDragSubject,
    targetWorkspaceName: String?,
    targetsNewWorkspace: Bool,
    targetProjectId: WorkspaceProjectId? = nil,
    targetMonitorScopeId: String? = nil,
) -> WorkspaceSidebarDropPreviewViewModel {
    let moveNode = dragSubjectNode(for: sourceWindow, subject: subject)
    let isTabGroup = moveNode is TilingContainer
    let sourceLabel = sidebarDragSourceTitle(for: sourceWindow, subject: subject)
    let appName = sourceWindow.app.name ?? sourceWindow.app.rawAppBundleId ?? "Window"
    return WorkspaceSidebarDropPreviewViewModel(
        sourceWindowId: sourceWindow.windowId,
        label: sourceLabel,
        appName: appName,
        appBundleIdentifier: sourceWindow.app.rawAppBundleId,
        appBundlePath: sourceWindow.app.bundlePath,
        targetWorkspaceName: targetWorkspaceName,
        targetsNewWorkspace: targetsNewWorkspace,
        targetProjectId: targetProjectId,
        targetMonitorScopeId: targetMonitorScopeId,
        isTabGroup: isTabGroup,
        windowCount: max(moveNode.allLeafWindowsRecursive.count, 1),
        tabItems: workspaceSidebarDropPreviewTabs(for: moveNode, isTabGroup: isTabGroup),
    )
}

@MainActor
private func workspaceSidebarDropPreviewTabs(
    for moveNode: TreeNode,
    isTabGroup: Bool,
) -> [WorkspaceSidebarDropPreviewTabItem] {
    guard isTabGroup else { return [] }
    return moveNode.allLeafWindowsRecursive.map { window in
        let appName = window.app.name ?? window.app.rawAppBundleId ?? "Window"
        return WorkspaceSidebarDropPreviewTabItem(
            title: cachedWindowTitle(for: window)?.takeIf { $0 != appName } ?? appName,
            appName: appName,
            appBundleIdentifier: window.app.rawAppBundleId,
            appBundlePath: window.app.bundlePath,
        )
    }
}

@MainActor
func selectWorkspaceSidebarProject(
    _ projectId: WorkspaceProjectId,
    viewModel: TrayMenuModel = TrayMenuModel.shared,
    targetMonitorScopeId: String? = nil,
) {
    let knownProjects = workspaceProjects()
    let resolvedTargetScopeId = targetMonitorScopeId ?? viewModel.workspaceSidebarTargetMonitorScopeId
    debugWorkspaceSidebarProjectLog(
        "selectProjectBegin project=\(projectId.rawValue) known=\(knownProjects.map(\.id.rawValue)) targetScope=\(resolvedTargetScopeId) activeBefore=\(viewModel.workspaceSidebarActiveProjectId.rawValue)"
    )
    guard knownProjects.contains(where: { $0.id == projectId }) else {
        debugWorkspaceSidebarProjectLog("selectProjectAbort unknownProject=\(projectId.rawValue)")
        return
    }
    runWorkspaceSidebarSession(prioritizeFocusSync: true) {
        let monitor = workspaceSidebarTargetMonitor(
            scopeId: targetMonitorScopeId ?? viewModel.workspaceSidebarTargetMonitorScopeId
        )
        debugWorkspaceSidebarProjectLog(
            "selectProjectSession project=\(projectId.rawValue) monitor=\(monitor.monitorAppKitNsScreenScreensId) visibleBefore=\(monitor.activeWorkspace.name) activeProjectBefore=\(activeWorkspaceProjectId(for: monitor).rawValue)"
        )
        if let workspace = switchWorkspaceProject(projectId, on: monitor) {
            debugWorkspaceSidebarProjectLog(
                "selectProjectSwitchResult project=\(projectId.rawValue) workspace=\(workspace.name) workspaceProject=\(workspace.projectId.rawValue)"
            )
            _ = workspace.focusWorkspace()
            viewModel.workspaceSidebarActiveProjectId = projectId
        } else {
            debugWorkspaceSidebarProjectLog("selectProjectSwitchResult project=\(projectId.rawValue) workspace=nil")
        }
        debugWorkspaceSidebarProjectLog(
            "selectProjectEnd project=\(projectId.rawValue) activeAfter=\(viewModel.workspaceSidebarActiveProjectId.rawValue)"
        )
    }
}

@MainActor
@discardableResult
func createWorkspaceSidebarProject(
    displayName: String? = nil,
    viewModel: TrayMenuModel = TrayMenuModel.shared,
    targetMonitorScopeId: String? = nil,
    onCreated: ((WorkspaceProjectId) -> Void)? = nil,
) -> Task<Void, Never>? {
    runWorkspaceSidebarSession(prioritizeFocusSync: true) {
        let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let displayName {
            guard !displayName.isEmpty else { throw WorkspaceMutationError.emptyName }
            guard !workspaceProjects().contains(where: {
                $0.name.caseInsensitiveCompare(displayName) == .orderedSame
            }) else {
                throw WorkspaceMutationError.duplicateProjectName(displayName)
            }
        }
        let project = createWorkspaceProject()
        if let displayName {
            try renameWorkspaceProject(project.id, displayName: displayName)
        }
        onCreated?(project.id)
    }
}

@MainActor
func createWorkspaceSidebarFolder(
    viewModel: TrayMenuModel = TrayMenuModel.shared,
    targetMonitorScopeId: String? = nil,
) {
    runWorkspaceSidebarSession {
        let monitor = workspaceSidebarTargetMonitor(
            scopeId: targetMonitorScopeId ?? viewModel.workspaceSidebarTargetMonitorScopeId
        )
        guard createWorkspaceFolderFromWorkspace(monitor.activeWorkspace.name) != nil else {
            showWorkspaceSidebarError("Open a window in this tab before creating a folder.")
            return
        }
    }
}

@MainActor
@discardableResult
func createSidebarFolderFromWorkspace(_ workspaceName: String) -> WorkspaceProjectId? {
    createWorkspaceFolderFromWorkspace(workspaceName)?.backingProjectId
}

@MainActor
@discardableResult
func createWorkspaceFolderFromWorkspace(_ workspaceName: String) -> WorkspaceFolderId? {
    materializePersistedWorkspaceProjects()
    guard let workspace = Workspace.existing(byName: workspaceName),
          !workspace.isArchived,
          workspaceHasLifecycleWindows(workspace) || workspace.isConfiguredPersistent
    else { return nil }

    let folder = createWorkspaceFolder(in: workspace.projectId)
    do {
        try renameWorkspaceFolder(folder.id, displayName: workspaceSidebarDefaultFolderName(projectId: workspace.projectId))
    } catch {
        winMuxWorkspaceState.removeFolder(folder.id)
        return nil
    }
    workspace.assignFolder(folder.id)
    var storedFolder = winMuxWorkspaceState.workspaceFoldersById[folder.id].orDie()
    storedFolder.workspaceOrder = [workspace.id]
    winMuxWorkspaceState.workspaceFoldersById[folder.id] = storedFolder
    setWorkspaceSidebarFolderExpanded(folder.id, isExpanded: true)
    checkWorkspaceHierarchyInvariants()
    return folder.id
}

@MainActor
private func moveWorkspaceSidebarFolderProjectToTop(_ projectId: WorkspaceProjectId) {
    winMuxWorkspaceState.normalizeDefaultProjectFolderOrder()
    let orderedFolderIds = workspaceFoldersInSidebarOrder()
        .filter { $0.id != workspaceFolderDefaultId }
        .map(\.id)
    let folderId = WorkspaceFolderId(projectId)
    guard orderedFolderIds.first != folderId,
          orderedFolderIds.contains(folderId)
    else { return }

    let reorderedFolderIds = [folderId] + orderedFolderIds.filter { $0 != folderId }
    for (offset, folderId) in reorderedFolderIds.enumerated() {
        guard var folder = winMuxWorkspaceState.workspaceFoldersById[folderId] else { continue }
        folder.order = offset + 1
        winMuxWorkspaceState.workspaceFoldersById[folderId] = folder
    }
    if var project = winMuxWorkspaceState.projectsById[workspaceProjectDefaultId] {
        project.folderOrder = reorderedFolderIds
        if winMuxWorkspaceState.workspaceFoldersById[workspaceFolderDefaultId] != nil {
            project.folderOrder.append(workspaceFolderDefaultId)
        }
        winMuxWorkspaceState.projectsById[workspaceProjectDefaultId] = project
    }
}

@MainActor
private func workspaceSidebarDefaultFolderName(projectId: WorkspaceProjectId) -> String {
    let visibleFolderIds = Set(userFacingWorkspaces(
        orderedWorkspacesForPresentation(),
        focusedWorkspace: focus.workspace,
    ).lazy
        .map(\.folderId)
        .filter {
            $0 != winMuxWorkspaceState.unfoldedFolderId(for: projectId) &&
                winMuxWorkspaceState.workspaceFoldersById[$0]?.projectId == projectId
        })
    let usedOrdinals = Set(visibleFolderIds.compactMap { folderId in
        winMuxWorkspaceState.workspaceFoldersById[folderId]
            .flatMap { workspaceSidebarGeneratedFolderOrdinal($0.name) }
    })
    var ordinal = 1
    while usedOrdinals.contains(ordinal) {
        ordinal += 1
    }
    return "Folder \(ordinal)"
}

private func workspaceSidebarGeneratedFolderOrdinal(_ name: String) -> Int? {
    let normalizedName = workspaceSidebarFolderDisplayName(name)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "folder "
    guard normalizedName.lowercased().hasPrefix(prefix) else { return nil }
    let suffix = normalizedName.dropFirst(prefix.count)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let ordinal = Int(suffix), ordinal > 0 else { return nil }
    return ordinal
}

@MainActor
func renameWorkspaceSidebarProject(_ projectId: WorkspaceProjectId, displayName: String) {
    runWorkspaceSidebarSession {
        try renameWorkspaceProject(projectId, displayName: displayName)
    }
}

@MainActor
func renameWorkspaceSidebarFolder(_ folderId: WorkspaceFolderId, displayName: String) {
    runWorkspaceSidebarSession {
        try renameWorkspaceFolder(folderId, displayName: displayName)
    }
}

@MainActor
func setWorkspaceSidebarProjectColor(_ project: WorkspaceSidebarProjectViewModel, colorHex: String?) {
    runWorkspaceSidebarSession {
        let normalizedColorHex = colorHex.flatMap(normalizedWorkspaceSidebarColorHex)
        if let normalizedColorHex {
            config.workspaceSidebar.projectColors[project.id.rawValue] = normalizedColorHex
        } else {
            config.workspaceSidebar.projectColors.removeValue(forKey: project.id.rawValue)
        }
        if !isUnitTest {
            try persistWorkspaceSidebarProjectColor(projectId: project.id.rawValue, colorHex: normalizedColorHex)
        }
    }
}

@MainActor
func setWorkspaceSidebarFolderColor(_ folderId: WorkspaceFolderId, colorHex: String?) {
    runWorkspaceSidebarSession {
        let normalizedColorHex = colorHex.flatMap(normalizedWorkspaceSidebarColorHex)
        if let normalizedColorHex {
            config.workspaceSidebar.folderColors[folderId.rawValue] = normalizedColorHex
        } else {
            config.workspaceSidebar.folderColors.removeValue(forKey: folderId.rawValue)
        }
        if !isUnitTest {
            try persistWorkspaceSidebarFolderColor(folderId: folderId.rawValue, colorHex: normalizedColorHex)
        }
    }
}

@MainActor
func deleteWorkspaceSidebarFolder(_ folderId: WorkspaceFolderId) {
    guard canDeleteWorkspaceFolder(folderId) else { return }
    runWorkspaceSidebarSession {
        try deleteWorkspaceFolder(folderId)
    }
}

@MainActor
func deleteWorkspaceSidebarProject(
    _ project: WorkspaceSidebarProjectViewModel,
    viewModel: TrayMenuModel = TrayMenuModel.shared,
) {
    guard canDeleteWorkspaceProject(project.id) else { return }
    guard confirmWorkspaceSidebarProjectDeletion(project) else { return }
    runWorkspaceSidebarSession(
        postRefresh: workspaceSidebarProjectDeletionPostRefreshPolicy(
            for: config.workspaceSidebar.projectDeletionAction
        )
    ) {
        try await deleteWorkspaceProjectFromSidebar(project.id)
    }
}

@MainActor
private func confirmWorkspaceSidebarProjectDeletion(_ project: WorkspaceSidebarProjectViewModel) -> Bool {
    let windowCount = windowsInWorkspaceProject(project.id).count
    guard windowCount > 0 else { return true }

    let alert = NSAlert()
    switch config.workspaceSidebar.projectDeletionAction {
        case .closeWindows:
            alert.messageText = "Close Project Windows?"
            alert.informativeText = """
            WinMux will ask macOS to close \(windowCount) window\(windowCount == 1 ? "" : "s") in “\(project.displayName)”. Apps may show their own confirmation dialogs for unsaved work. If any window stays open, WinMux will keep the project.
            """
            alert.addButton(withTitle: "Close Project")
        case .moveWindowsToFallback:
            alert.messageText = "Delete Project?"
            alert.informativeText = """
            WinMux will delete “\(project.displayName)” and move \(windowCount) window\(windowCount == 1 ? "" : "s") to another project.
            """
            alert.addButton(withTitle: "Delete project")
    }
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .warning
    return alert.runModal() == .alertFirstButtonReturn
}

@MainActor
func renameWorkspaceFromSidebar(_ workspaceName: String, displayName: String) {
    debugWorkspaceSidebarRenameLog("renameWorkspaceFromSidebar workspace=\(workspaceName) displayName=\(displayName)")
    runWorkspaceSidebarSession {
        try renameWorkspaceForSidebar(workspaceName: workspaceName, displayName: displayName)
    }
}

@MainActor
func closeWorkspaceFromSidebar(_ workspace: WorkspaceSidebarWorkspaceViewModel) {
    guard confirmWorkspaceSidebarTabClosure(workspace) else { return }
    runWorkspaceSidebarSession(postRefresh: .reconcileNativeWindowInventory) {
        try await closeWorkspaceWindowsFromSidebar(workspaceName: workspace.name)
    }
}

@MainActor
private func confirmWorkspaceSidebarTabClosure(_ workspace: WorkspaceSidebarWorkspaceViewModel) -> Bool {
    guard let liveWorkspace = Workspace.existing(byName: workspace.name) else { return true }
    let windowCount = windowsInWorkspace(liveWorkspace).count
    guard workspaceSidebarTabClosureRequiresConfirmation(windowCount: windowCount) else { return true }

    let alert = NSAlert()
    alert.messageText = "Close Tab Windows?"
    alert.informativeText = """
    WinMux will ask macOS to close \(windowCount) windows in “\(workspace.displayName)”. Apps may show their own confirmation dialogs for unsaved work. If any window stays open, WinMux will keep the tab.
    """
    alert.addButton(withTitle: "Close tab")
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .warning
    return alert.runModal() == .alertFirstButtonReturn
}

func workspaceSidebarTabClosureRequiresConfirmation(windowCount: Int) -> Bool {
    windowCount > 1
}

@MainActor
func reorderWorkspaceFromSidebar(_ workspaceName: String, folderId: WorkspaceFolderId, placement: WorkspaceReorderPlacement) {
    guard RunSessionGuard.isServerEnabled != nil else { return }
    let didReorder = reorderWorkspaceForSidebar(
        sourceWorkspaceName: workspaceName,
        folderId: folderId,
        placement: placement
    )
    guard didReorder else { return }
    runWorkspaceSidebarPostMutationSession()
}

@MainActor
func moveWorkspaceToFolderFromSidebar(
    _ workspaceName: String,
    folderId: WorkspaceFolderId
) {
    guard RunSessionGuard.isServerEnabled != nil else { return }
    guard moveWorkspaceToSidebarFolder(workspaceName, folderId: folderId) else { return }
    runWorkspaceSidebarPostMutationSession()
}

@MainActor
func moveWorkspaceToProjectFromSidebar(
    _ workspaceName: String,
    projectId: WorkspaceProjectId
) {
    guard RunSessionGuard.isServerEnabled != nil else { return }
    guard moveWorkspaceToProject(workspaceName: workspaceName, destinationProjectId: projectId) else { return }
    runWorkspaceSidebarPostMutationSession()
}

@MainActor
func moveWorkspaceSidebarFolderToProject(
    _ folderId: WorkspaceFolderId,
    projectId: WorkspaceProjectId
) {
    guard RunSessionGuard.isServerEnabled != nil else { return }
    guard moveWorkspaceFolderToProject(folderId: folderId, destinationProjectId: projectId) else { return }
    runWorkspaceSidebarPostMutationSession()
}

@MainActor
func reorderWorkspaceSidebarFolder(
    _ folderId: WorkspaceFolderId,
    placement: WorkspaceSidebarFolderReorderPlacement
) {
    runWorkspaceSidebarSession {
        guard reorderWorkspaceFolderForSidebar(sourceFolderId: folderId, placement: placement) else { return }
    }
}

@MainActor
func mergeWorkspacesFromSidebar(
    sourceWorkspaceName: String,
    targetWorkspaceName: String,
    position: WindowStackSplitPosition
) {
    runWorkspaceSidebarSession {
        guard mergeWorkspaceTab(
            sourceWorkspaceName: sourceWorkspaceName,
            targetWorkspaceName: targetWorkspaceName,
            position: position
        ) else { return }
    }
}

@MainActor
@discardableResult
func createSidebarFolderFromWorkspaces(
    sourceWorkspaceName: String,
    targetWorkspaceName: String
) -> Bool {
    materializePersistedWorkspaceProjects()
    guard sourceWorkspaceName != targetWorkspaceName,
          let sourceWorkspace = Workspace.existing(byName: sourceWorkspaceName),
          let targetWorkspace = Workspace.existing(byName: targetWorkspaceName),
          !sourceWorkspace.isArchived,
          !targetWorkspace.isArchived
    else { return false }
    if let sourceMonitor = sourceWorkspace.visibleMonitor,
       let targetMonitor = targetWorkspace.visibleMonitor,
       sourceMonitor.rect.topLeftCorner != targetMonitor.rect.topLeftCorner
    {
        return false
    }

    let folderWorkspaces = orderedWorkspacesForPresentation()
        .filter { $0 == sourceWorkspace || $0 == targetWorkspace }
    let orderedFolderWorkspaces = folderWorkspaces.count == 2 ? folderWorkspaces : [targetWorkspace, sourceWorkspace]
    guard sourceWorkspace.projectId == targetWorkspace.projectId else { return false }
    let folder = createWorkspaceFolder(in: sourceWorkspace.projectId)
    do {
        try renameWorkspaceFolder(folder.id, displayName: workspaceSidebarDefaultFolderName(projectId: sourceWorkspace.projectId))
    } catch {
        winMuxWorkspaceState.removeFolder(folder.id)
        return false
    }
    for workspace in orderedFolderWorkspaces {
        workspace.assignFolder(folder.id)
    }
    var storedFolder = winMuxWorkspaceState.workspaceFoldersById[folder.id].orDie()
    storedFolder.workspaceOrder = orderedFolderWorkspaces.map(\.id)
    winMuxWorkspaceState.workspaceFoldersById[folder.id] = storedFolder
    setWorkspaceSidebarFolderExpanded(folder.id, isExpanded: true)
    checkWorkspaceHierarchyInvariants()
    return true
}

@MainActor
@discardableResult
func moveWorkspaceToSidebarFolder(
    _ workspaceName: String,
    projectId: WorkspaceProjectId
) -> Bool {
    moveWorkspaceToSidebarFolder(workspaceName, folderId: WorkspaceFolderId(projectId))
}

@MainActor
@discardableResult
func moveWorkspaceToSidebarFolder(
    _ workspaceName: String,
    folderId: WorkspaceFolderId
) -> Bool {
    materializePersistedWorkspaceProjects()
    guard var folder = winMuxWorkspaceState.workspaceFoldersById[folderId],
          let workspace = Workspace.existing(byName: workspaceName),
          workspace.folderId != folderId,
          workspace.projectId == folder.projectId,
          !workspace.isArchived
    else { return false }
    workspace.assignFolder(folderId)
    folder.workspaceOrder.removeAll { $0 == workspace.id }
    folder.workspaceOrder.append(workspace.id)
    winMuxWorkspaceState.workspaceFoldersById[folderId] = folder
    setWorkspaceSidebarFolderExpanded(folderId, isExpanded: true)
    checkWorkspaceHierarchyInvariants()
    return true
}

@MainActor
func mergeWorkspaceIntoActiveViewFromSidebarIfPossible(
    sourceWorkspaceName: String,
    pointer: CGPoint,
    position: WindowStackSplitPosition = .right
) {
    runWorkspaceSidebarSession {
        guard mergeWorkspaceIntoActiveViewFromSidebar(
            sourceWorkspaceName: sourceWorkspaceName,
            pointer: pointer,
            position: position
        ) else { return }
    }
}

@MainActor
func mergeWorkspaceIntoActiveTabGroupFromSidebarIfPossible(
    sourceWorkspaceName: String,
    pointer: CGPoint,
    targetWindowId: UInt32
) {
    runWorkspaceSidebarSession {
        guard mergeWorkspaceIntoActiveTabGroupFromSidebar(
            sourceWorkspaceName: sourceWorkspaceName,
            pointer: pointer,
            targetWindowId: targetWindowId
        ) else { return }
    }
}

@MainActor
@discardableResult
func mergeWorkspaceIntoActiveTabGroupFromSidebar(
    sourceWorkspaceName: String,
    pointer: CGPoint,
    targetWindowId: UInt32? = nil
) -> Bool {
    guard let sourceWorkspace = Workspace.existing(byName: sourceWorkspaceName),
          WorkspaceSidebarPanel.panel(containing: pointer) == nil
    else { return false }
    let targetWorkspace = pointer.monitorApproximation.activeWorkspace
    guard targetWorkspace != sourceWorkspace,
          !sourceWorkspace.isArchived,
          !targetWorkspace.isArchived,
          !projectsAreEnabled() || sourceWorkspace.projectId == targetWorkspace.projectId
    else { return false }
    guard let targetWindow = targetWindowId.flatMap(Window.get)
        ?? targetWorkspace.rootTilingContainer.mostRecentWindowRecursive
        ?? targetWorkspace.rootTilingContainer.anyLeafWindowRecursive
    else { return false }
    guard let targetWindowWorkspace = targetWindow.nodeWorkspace,
          targetWindowWorkspace === targetWorkspace
    else { return false }
    if let sourceMonitor = sourceWorkspace.visibleMonitor,
       let targetMonitor = targetWorkspace.visibleMonitor,
       sourceMonitor.rect.topLeftCorner != targetMonitor.rect.topLeftCorner
    {
        return false
    }

    let sourceWindows = sourceWorkspace.rootTilingContainer.allLeafWindowsRecursive
    guard !sourceWindows.isEmpty else { return false }
    syncClosedWindowsCacheToCurrentWorld()
    suppressPostDragAxObserverEvents(for: sourceWindows.map(\.windowId) + [targetWindow.windowId])
    for sourceWindow in sourceWindows {
        createOrAppendWindowTabStack(sourceWindow: sourceWindow, onto: targetWindow)
    }
    moveWorkspaceFloatingContent(from: sourceWorkspace, to: targetWorkspace)
    moveWorkspaceNativeContent(from: sourceWorkspace, to: targetWorkspace)

    if let sourceMonitor = sourceWorkspace.visibleMonitor, targetWorkspace.visibleMonitor == nil {
        _ = sourceMonitor.setActiveWorkspace(targetWorkspace)
    }
    if focus.workspace == sourceWorkspace {
        _ = setFocus(to: targetWorkspace.toLiveFocus())
    }
    _ = targetWorkspace.focusWorkspace()
    removeWorkspaceFromRegistry(sourceWorkspace)
    checkWorkspaceHierarchyInvariants()
    return true
}

@MainActor
@discardableResult
func mergeWorkspaceIntoActiveViewFromSidebar(
    sourceWorkspaceName: String,
    pointer: CGPoint,
    position: WindowStackSplitPosition = .right
) -> Bool {
    guard let sourceWorkspace = Workspace.existing(byName: sourceWorkspaceName) else { return false }
    guard WorkspaceSidebarPanel.panel(containing: pointer) == nil else { return false }
    let monitor = pointer.monitorApproximation
    let targetWorkspace = monitor.activeWorkspace
    guard targetWorkspace != sourceWorkspace else { return false }
    return mergeWorkspaceTab(
        sourceWorkspaceName: sourceWorkspaceName,
        targetWorkspaceName: targetWorkspace.name,
        position: position,
    )
}

@MainActor
@discardableResult
func mergeWorkspaceTab(
    sourceWorkspaceName: String,
    targetWorkspaceName: String,
    position: WindowStackSplitPosition
) -> Bool {
    guard sourceWorkspaceName != targetWorkspaceName,
          let sourceWorkspace = Workspace.existing(byName: sourceWorkspaceName),
          let targetWorkspace = Workspace.existing(byName: targetWorkspaceName),
          !sourceWorkspace.isArchived,
          !targetWorkspace.isArchived
    else { return false }
    guard !projectsAreEnabled() || sourceWorkspace.projectId == targetWorkspace.projectId else {
        return false
    }
    if let sourceMonitor = sourceWorkspace.visibleMonitor,
       let targetMonitor = targetWorkspace.visibleMonitor,
       sourceMonitor.rect.topLeftCorner != targetMonitor.rect.topLeftCorner
    {
        return false
    }

    let movedWindows = sourceWorkspace.allLeafWindowsRecursive.map(\.windowId)
    syncClosedWindowsCacheToCurrentWorld()
    suppressPostDragAxObserverEvents(for: movedWindows)

    mergeWorkspaceTilingContent(
        from: sourceWorkspace,
        into: targetWorkspace,
        position: position
    )
    moveWorkspaceFloatingContent(from: sourceWorkspace, to: targetWorkspace)
    moveWorkspaceNativeContent(from: sourceWorkspace, to: targetWorkspace)

    if let sourceMonitor = sourceWorkspace.visibleMonitor, targetWorkspace.visibleMonitor == nil {
        _ = sourceMonitor.setActiveWorkspace(targetWorkspace)
    }
    if focus.workspace == sourceWorkspace {
        _ = setFocus(to: targetWorkspace.toLiveFocus())
    }
    _ = targetWorkspace.focusWorkspace()
    removeWorkspaceFromRegistry(sourceWorkspace)
    checkWorkspaceHierarchyInvariants()
    return true
}

@MainActor
private func mergeWorkspaceTilingContent(
    from sourceWorkspace: Workspace,
    into targetWorkspace: Workspace,
    position: WindowStackSplitPosition
) {
    let sourceRoot = sourceWorkspace.rootTilingContainer
    guard !sourceRoot.children.isEmpty else { return }
    let targetRoot = workspaceSiblingInsertionRoot(targetWorkspace, orientation: position.orientation)
    let movedNode = sourceRoot.children.singleOrNil() ?? sourceRoot
    movedNode.bind(
        to: targetRoot,
        adaptiveWeight: WEIGHT_AUTO,
        index: position.isPositive ? INDEX_BIND_LAST : 0
    )
}

@MainActor
private func moveWorkspaceFloatingContent(from sourceWorkspace: Workspace, to targetWorkspace: Workspace) {
    for window in sourceWorkspace.floatingWindows {
        window.bind(to: targetWorkspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
}

@MainActor
private func moveWorkspaceNativeContent(from sourceWorkspace: Workspace, to targetWorkspace: Workspace) {
    if let fullscreenContainer = sourceWorkspace.existingMacOsNativeFullscreenWindowsContainer {
        for window in fullscreenContainer.children.filterIsInstance(of: Window.self) {
            window.bind(to: targetWorkspace.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
        }
    }
    if let hiddenAppsContainer = sourceWorkspace.existingMacOsNativeHiddenAppsWindowsContainer {
        for window in hiddenAppsContainer.children.filterIsInstance(of: Window.self) {
            window.bind(to: targetWorkspace.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
        }
    }
    for window in workspaceOwnedMinimizedWindows(sourceWorkspace) {
        switch window.layoutReason {
            case .macos(let prevParentKind, _):
                window.layoutReason = .macos(prevParentKind: prevParentKind, prevWorkspaceName: targetWorkspace.name)
            case .standard:
                break
        }
    }
}

@MainActor
func focusWindowFromSidebar(_ windowId: UInt32) {
    WorkspaceSidebarPanel.suppressEdgeTrapForWorkspaceActivation()
    runWorkspaceSidebarSession(prioritizeFocusSync: true) {
        guard let window = Window.get(byId: windowId),
              let liveFocus = window.toLiveFocusOrNil()
        else {
            if let fallbackWorkspace = workspaceSidebarFallbackWorkspaceName(for: windowId) {
                _ = Workspace.existing(byName: fallbackWorkspace)?.focusWorkspace()
            }
            return
        }
        _ = setFocus(to: liveFocus)
    }
}

@MainActor
func workspaceSidebarFallbackWorkspaceName(for windowId: UInt32) -> String? {
    for workspace in TrayMenuModel.shared.workspaceSidebarWorkspaces {
        for item in workspace.items {
            switch item.kind {
                case .window(let window) where window.windowId == windowId:
                    return window.workspaceName
                case .tabGroup(let group) where group.representativeWindowId == windowId:
                    return group.workspaceName
                case .tabGroup(let group):
                    if group.tabs.contains(where: { $0.windowId == windowId }) {
                        return group.workspaceName
                    }
                case .window:
                    continue
            }
        }
    }
    return nil
}

@MainActor
func updateSidebarWindowDrag(_ windowId: UInt32, subject: WindowDragSubject = .window, pointer: CGPoint? = nil) {
    if let pointer {
        MousePointerTracker.shared.note(point: pointer)
        postWorkspaceSidebarDragPointerNotification(workspaceSidebarDragPointerChangedNotification, pointer: pointer)
    }
    guard let window = Window.get(byId: windowId) else {
        clearWorkspaceSidebarDropPreview()
        clearPendingWindowDragIntent()
        WindowDragCursorProxyPanel.shared.hide()
        clearActiveWorkspaceSidebarDrag()
        return
    }
    beginActiveWorkspaceSidebarDrag(windowId: window.windowId, subject: subject)
    let point = MousePointerTracker.shared.currentSample.point
    updateActiveWorkspaceSidebarDragPreview(sourceWindow: window, subject: subject)
    beginWindowMoveWithMouseSessionIfNeeded(
        windowId: window.windowId,
        subject: subject,
        detachOrigin: .window,
        startedInSidebar: true,
        anchorRect: resolvedDraggedWindowAnchorRect(for: window, subject: subject),
        refreshActualRects: true,
    )
    WindowMouseInteractionDriver.shared.startMove(
        windowId: window.windowId,
        subject: subject,
        detachOrigin: .window,
        startedInSidebar: true,
    )
    _ = updatePendingWindowDragIntent(
        sourceWindow: window,
        mouseLocation: point,
        subject: subject,
        detachOrigin: .window,
    )
}

@MainActor
func finishSidebarWindowDrag(pointer: CGPoint? = nil) {
    if let pointer {
        MousePointerTracker.shared.note(point: pointer)
        postWorkspaceSidebarDragPointerNotification(workspaceSidebarDragPointerEndedNotification, pointer: pointer)
    }
    let didCommitSidebarDrop = commitActiveWorkspaceSidebarDragIfPossible()
    clearActiveWorkspaceSidebarDrag()
    if didCommitSidebarDrop {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        scheduleRefreshSession(.resetManipulatedWithMouse, optimisticallyPreLayoutWorkspaces: true)
        return
    }
    Task { @MainActor in
        try? await resetManipulatedWithMouseIfPossible()
    }
    clearWorkspaceSidebarDropPreview()
    WindowDragCursorProxyPanel.shared.hide()
}

@MainActor
func finishWorkspaceSidebarDragAfterGlobalMouseUp() {
    let hasSidebarWindowDragState = currentActiveWorkspaceSidebarDrag() != nil
    let hasCursorProxy = WindowDragCursorProxyPanel.shared.currentContent != nil || WindowDragCursorProxyPanel.shared.isVisible
    guard hasSidebarWindowDragState || hasCursorProxy else {
        postWorkspaceSidebarDragPointerNotification(
            workspaceSidebarDragPointerEndedNotification,
            pointer: MousePointerTracker.shared.currentSample.point
        )
        resetWorkspaceSidebarItemDrag()
        return
    }
    if hasSidebarWindowDragState {
        finishSidebarWindowDrag()
    } else {
        clearWorkspaceSidebarDropPreview()
        WindowDragCursorProxyPanel.shared.hide()
    }
    resetWorkspaceSidebarItemDrag()
}

@MainActor
private func postWorkspaceSidebarDragPointerNotification(_ name: Notification.Name, pointer: CGPoint) {
    NotificationCenter.default.post(
        name: name,
        object: nil,
        userInfo: [workspaceSidebarDragPointerUserInfoKey: NSValue(point: pointer)]
    )
}

@MainActor
private func workspaceSidebarDragTarget(for sourceWindow: Window, subject: WindowDragSubject) -> WorkspaceSidebarDropTargetKind? {
    let point = MousePointerTracker.shared.currentSample.point
    guard WorkspaceSidebarPanel.panel(containing: point) != nil else { return nil }
    guard let target = workspaceSidebarDropTarget(at: point)?.kind else { return nil }
    guard isActionableSidebarDropTarget(sourceWindow: sourceWindow, subject: subject, target: target) else { return nil }
    return target
}

@MainActor
func refreshActiveWorkspaceSidebarDragPreviewIfNeeded() {
    guard let activeDrag = currentActiveWorkspaceSidebarDrag(),
          let sourceWindow = Window.get(byId: activeDrag.windowId)
    else { return }
    updateActiveWorkspaceSidebarDragPreview(sourceWindow: sourceWindow, subject: activeDrag.subject)
}

@MainActor
private func updateActiveWorkspaceSidebarDragPreview(sourceWindow: Window, subject: WindowDragSubject) {
    showWorkspaceSidebarDragCursorPreview(
        sourceWindow: sourceWindow,
        subject: subject,
        point: MousePointerTracker.shared.currentSample.point
    )
    guard let target = workspaceSidebarDragTarget(for: sourceWindow, subject: subject) else {
        clearWorkspaceSidebarDropPreview()
        return
    }
    previewWorkspaceSidebarDrop(sourceWindow.windowId, subject: subject, target: target)
}

@MainActor
func commitActiveWorkspaceSidebarDrag(to target: WorkspaceSidebarDropTargetKind) -> Bool {
    guard let activeDrag = currentActiveWorkspaceSidebarDrag(),
          let sourceWindow = Window.get(byId: activeDrag.windowId),
          isActionableSidebarDropTarget(sourceWindow: sourceWindow, subject: activeDrag.subject, target: target)
    else {
        clearWorkspaceSidebarDropPreview()
        WindowDragCursorProxyPanel.shared.hide()
        return false
    }
    clearWorkspaceSidebarDropPreview()
    WindowDragCursorProxyPanel.shared.hide()
    switch target {
        case .workspace(let workspaceName):
            if activeDrag.subject == .group {
                return applySidebarSource(sourceWindow.windowId, subject: .group, toWorkspace: workspaceName)
            } else {
                return applySidebarSource(sourceWindow.windowId, subject: .window, toWorkspace: workspaceName)
            }
        case .folder(let projectId, let monitorScopeId):
            return applySidebarSourceToNewWorkspace(
                sourceWindow.windowId,
                subject: activeDrag.subject,
                folderId: WorkspaceFolderId(projectId),
                monitorScopeId: monitorScopeId
            )
        case .newWorkspace(let projectId, let monitorScopeId):
            if activeDrag.subject == .group {
                return applySidebarSourceToNewWorkspace(
                    sourceWindow.windowId,
                    subject: .group,
                    projectId: projectId,
                    monitorScopeId: monitorScopeId
                )
            } else {
                return applySidebarSourceToNewWorkspace(
                    sourceWindow.windowId,
                    subject: .window,
                    projectId: projectId,
                    monitorScopeId: monitorScopeId
                )
            }
        case .monitor:
            return false
    }
}

@MainActor
private func commitActiveWorkspaceSidebarDragIfPossible() -> Bool {
    guard let activeDrag = currentActiveWorkspaceSidebarDrag(),
          let sourceWindow = Window.get(byId: activeDrag.windowId),
          let target = workspaceSidebarDragTarget(for: sourceWindow, subject: activeDrag.subject)
    else {
        clearWorkspaceSidebarDropPreview()
        WindowDragCursorProxyPanel.shared.hide()
        return false
    }
    return commitActiveWorkspaceSidebarDrag(to: target)
}
