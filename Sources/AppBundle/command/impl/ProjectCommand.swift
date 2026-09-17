import Common

struct ProjectCommand: Command {
    let args: ProjectCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let monitor = target.workspace.workspaceMonitor
        let currentProjectId = target.workspace.projectId
        guard let project = resolveProjectTarget(
            args.target.val,
            currentProjectId: currentProjectId,
            wrapAround: args.wrapAround,
        ) else {
            return io.err("Can't resolve project target")
        }
        if project.id == currentProjectId {
            if !args.failIfNoop {
                io.err("Project '\(project.name)' is already focused. Tip: use --fail-if-noop to exit with non-zero code")
            }
            return !args.failIfNoop
        }
        guard let workspace = switchWorkspaceProject(project.id, on: monitor) else {
            return io.err("Can't switch to project '\(project.name)'")
        }
        return workspace.focusWorkspace()
    }
}

@MainActor
func resolveWorkspaceSidebarFolderTarget(
    _ target: ProjectTarget,
    currentFolderId: WorkspaceFolderId,
    wrapAround: Bool,
    monitor: Monitor? = nil
) -> WorkspaceFolderId? {
    let folderIds = workspaceSidebarFolderNavigationFolderIds(monitor: monitor)
    guard !folderIds.isEmpty else { return nil }
    switch target {
        case .defaultFolder:
            return workspaceFolderDefaultId
        case .index(let index):
            return folderIds.getOrNil(atIndex: index - 1)
        case .relative(let nextPrev):
            let currentIndex = folderIds.firstIndex(of: currentFolderId)
                ?? folderIds.firstIndex(of: workspaceFolderDefaultId)
            guard let currentIndex else { return nil }
            let targetIndex = currentIndex + (nextPrev == .next ? 1 : -1)
            return wrapAround ? folderIds.get(wrappingIndex: targetIndex) : folderIds.getOrNil(atIndex: targetIndex)
    }
}

@MainActor
func workspaceSidebarFolderNavigationProjectIds(monitor: Monitor? = nil) -> [WorkspaceProjectId] {
    workspaceSidebarFolderNavigationFolderIds(monitor: monitor).map(\.backingProjectId)
}

@MainActor
func workspaceSidebarFolderNavigationFolderIds(monitor: Monitor? = nil) -> [WorkspaceFolderId] {
    let projectId = monitor.map { activeWorkspaceProjectId(for: $0) } ?? focus.workspace.projectId
    return workspaceFolders(in: projectId).map(\.id)
}

@MainActor
func workspaceSidebarFolderNavigationSections(monitor: Monitor? = nil) -> [WorkspaceSidebarFolderSection] {
    let projectId = monitor.map { activeWorkspaceProjectId(for: $0) } ?? focus.workspace.projectId
    return workspaceSidebarFolderSections(
        projectId: projectId,
        workspaces: workspaceSidebarFolderNavigationWorkspaceViewModels(monitor: monitor),
        folders: workspaceSidebarFolderNavigationFolderViewModels(projectId: projectId),
    )
}

@MainActor
private func workspaceSidebarNavigationWorkspaces(monitor: Monitor?) -> [Workspace] {
    let projectId = monitor.map { activeWorkspaceProjectId(for: $0) } ?? focus.workspace.projectId
    return userFacingWorkspaces(orderedWorkspaces(in: projectId), focusedWorkspace: focus.workspace)
}

@MainActor
private func workspaceSidebarFolderNavigationFolderViewModels(
    projectId: WorkspaceProjectId
) -> [WorkspaceSidebarFolderViewModel] {
    workspaceFolders(in: projectId).map {
        WorkspaceSidebarFolderViewModel(
            id: $0.id,
            projectId: $0.projectId,
            displayName: $0.name,
            colorHex: config.workspaceSidebar.folderColors[$0.id.rawValue].flatMap(normalizedWorkspaceSidebarColorHex),
            isUnfolded: $0.id == winMuxWorkspaceState.unfoldedFolderId(for: projectId)
        )
    }
}

@MainActor
private func workspaceSidebarFolderNavigationWorkspaceViewModels(
    monitor: Monitor?
) -> [WorkspaceSidebarWorkspaceViewModel] {
    workspaceSidebarNavigationWorkspaces(monitor: monitor).map { workspace in
        let hasVisibleWindows = workspaceHasSidebarVisibleWindows(workspace)
        return WorkspaceSidebarWorkspaceViewModel(
            name: workspace.name,
            projectId: workspace.projectId,
            folderId: workspace.folderId,
            displayName: workspaceDisplayName(workspace.name),
            sidebarLabel: config.workspaceSidebar.workspaceLabels[workspace.name] ?? "",
            isGeneratedName: workspace.usesAutomaticDisplayName,
            tabSummary: WorkspaceSidebarTabSummaryViewModel(
                title: workspaceDisplayName(workspace.name),
                subtitle: nil,
                appBundleId: nil,
                appBundlePath: nil,
                windowCount: hasVisibleWindows ? max(workspace.allLeafWindowsRecursive.count, 1) : 0,
                isEmpty: !hasVisibleWindows
            ),
            monitorScopeId: workspaceSidebarMonitorScopeId(for: workspace.workspaceMonitor),
            monitorName: nil,
            isFocused: focus.workspace == workspace,
            isVisible: workspace.isVisible,
            items: []
        )
    }
}
