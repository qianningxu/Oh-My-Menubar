@MainActor
func buildWorkspaceSidebarWorkspaceViewModels(
    currentFocus: LiveFocus,
    workspaceLabels: [String: String],
    availableMonitors: [Monitor],
) async -> [WorkspaceSidebarWorkspaceViewModel] {
    await buildWorkspaceSidebarWorkspaceViewModels(
        from: orderedWorkspacesForPresentation(),
        currentFocus: currentFocus,
        workspaceLabels: workspaceLabels,
        availableMonitors: availableMonitors,
    )
}

@MainActor
func buildWorkspaceSidebarWorkspaceViewModels(
    from orderedWorkspaces: [Workspace],
    currentFocus: LiveFocus,
    workspaceLabels: [String: String],
    availableMonitors: [Monitor],
) async -> [WorkspaceSidebarWorkspaceViewModel] {
    let sourceWorkspaces = userFacingWorkspaces(
        orderedWorkspaces,
        focusedWorkspace: currentFocus.workspace,
    )
    // Keep this inventory local to the snapshot; the next refresh reads the tree again.
    let workspaceWindows = sourceWorkspaces.map { workspace in
        (workspace: workspace, windows: workspace.allLeafWindowsRecursive.filter(\.isBound))
    }
    let titleWindows = workspaceWindows.flatMap(\.windows)
    return await withWorkspaceSidebarCachedWindowTitles(titleWindows) {
        var viewModels: [WorkspaceSidebarWorkspaceViewModel] = []
        viewModels.reserveCapacity(sourceWorkspaces.count)
        for (workspace, windows) in workspaceWindows {
            viewModels.append(await makeWorkspaceSidebarWorkspaceViewModel(
                workspace,
                windows: windows,
                currentFocus: currentFocus,
                workspaceLabels: workspaceLabels,
                availableMonitors: availableMonitors,
            ))
        }
        return viewModels
    }
}

@MainActor
private func makeWorkspaceSidebarWorkspaceViewModel(
    _ workspace: Workspace,
    windows: [Window],
    currentFocus: LiveFocus,
    workspaceLabels: [String: String],
    availableMonitors: [Monitor],
) async -> WorkspaceSidebarWorkspaceViewModel {
    let workspaceMonitor = workspace.workspaceMonitor
    let sidebarLabel = workspaceLabels[workspace.name] ?? ""
    let tabSummary = await makeWorkspaceSidebarTabSummaryViewModel(
        workspace,
        windows: windows,
        currentFocus: currentFocus,
        sidebarLabel: sidebarLabel,
    )
    return WorkspaceSidebarWorkspaceViewModel(
        name: workspace.name,
        projectId: workspace.projectId,
        folderId: workspace.folderId,
        displayName: tabSummary.title,
        sidebarLabel: sidebarLabel,
        isGeneratedName: isSidebarDraftWorkspaceName(workspace.name) || workspace.usesAutomaticDisplayName,
        tabSummary: tabSummary,
        monitorScopeId: workspaceSidebarMonitorScopeId(for: workspaceMonitor),
        monitorName: availableMonitors.count > 1 ? workspaceMonitor.name : nil,
        isFocused: currentFocus.workspace == workspace,
        isVisible: workspace.isVisible,
        items: await buildWorkspaceSidebarItems(for: workspace, currentFocus: currentFocus),
    )
}

@MainActor
private func makeWorkspaceSidebarTabSummaryViewModel(
    _ workspace: Workspace,
    windows: [Window],
    currentFocus: LiveFocus,
    sidebarLabel: String,
) async -> WorkspaceSidebarTabSummaryViewModel {
    let representativeWindow =
        currentFocus.windowOrNil?.takeIf { $0.nodeWorkspace == workspace && $0.isBound } ??
        workspace.mostRecentWindowRecursive?.takeIf(\.isBound) ??
        windows.first
    let appName = representativeWindow?.app.name ?? representativeWindow?.app.rawAppBundleId
    let windowTitle: String?
    if let representativeWindow {
        windowTitle = await tabDisplayTitle(for: representativeWindow)
    } else {
        windowTitle = nil
    }
    let composedTitle = workspaceSidebarComposedTabTitle(
        appNames: orderedWorkspaceSidebarComposedTabWindows(
            windows,
            representativeWindow: representativeWindow,
        ).map(workspaceSidebarAppName)
    )
    let automaticTitle = windows.count > 1
        ? (composedTitle ?? appName ?? windowTitle ?? workspaceDisplayName(workspace.name))
        : (windowTitle ?? appName ?? workspaceDisplayName(workspace.name))
    let manualTitle = sidebarLabel.trimmingCharacters(in: .whitespacesAndNewlines).takeIf { !$0.isEmpty }
    let title = manualTitle ?? automaticTitle
    return WorkspaceSidebarTabSummaryViewModel(
        title: title,
        subtitle: nil,
        appBundleId: representativeWindow?.app.rawAppBundleId,
        appBundlePath: representativeWindow?.app.bundlePath,
        windowCount: windows.count,
        isEmpty: windows.isEmpty,
    )
}

func workspaceSidebarComposedTabTitle(appNames: [String]) -> String? {
    guard let firstAppName = appNames.first else { return nil }
    guard appNames.count > 1 else { return firstAppName }
    if appNames.count == 2,
       let secondAppName = appNames.dropFirst().first,
       secondAppName != firstAppName
    {
        return "\(firstAppName) & \(secondAppName)"
    }
    let otherCount = appNames.count - 1
    return "\(firstAppName) & \(otherCount) other\(otherCount == 1 ? "" : "s")"
}

private func orderedWorkspaceSidebarComposedTabWindows(
    _ windows: [Window],
    representativeWindow: Window?
) -> [Window] {
    guard let representativeWindow, windows.contains(representativeWindow) else { return windows }
    return [representativeWindow] + windows.filter { $0 != representativeWindow }
}

private func workspaceSidebarAppName(_ window: Window) -> String {
    window.app.name ?? window.app.rawAppBundleId ?? "Window"
}

func visibleWorkspaceNamesForSidebar(
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
    selectedMonitorScopeId: String,
    focusedMonitorScopeId: String,
    targetMonitorScopeId: String? = nil,
) -> Set<String> {
    let resolvedScopeId = workspaceSidebarTabListScopeId(
        selectedScopeId: selectedMonitorScopeId,
        targetMonitorScopeId: targetMonitorScopeId,
    )
    return Set(workspaces.filter {
        workspaceSidebarWorkspaceMatchesScope(
            $0,
            selectedScopeId: resolvedScopeId,
            focusedMonitorScopeId: focusedMonitorScopeId,
        )
    }.map(\.name))
}
