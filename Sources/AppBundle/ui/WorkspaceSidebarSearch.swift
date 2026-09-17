import Foundation

let workspaceSidebarSearchIsEnabled = false

func workspaceSidebarEffectiveSearchQuery(_ query: String) -> String {
    workspaceSidebarSearchIsEnabled ? query : ""
}

func workspaceSidebarFilteredWorkspacesByProject(
    _ workspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
    projects: [WorkspaceSidebarProjectViewModel],
    query: String,
) -> [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]] {
    let terms = workspaceSidebarSearchTerms(query)
    guard !terms.isEmpty else { return workspacesByProject }
    let projectNamesById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.displayName) })

    return workspacesByProject.mapValues { workspaces in
        workspaces.compactMap { workspace in
            workspaceSidebarFilteredWorkspace(
                workspace,
                projectName: projectNamesById[workspace.projectId],
                terms: terms,
            )
        }
    }
}

private func workspaceSidebarFilteredWorkspace(
    _ workspace: WorkspaceSidebarWorkspaceViewModel,
    projectName: String?,
    terms: [String],
) -> WorkspaceSidebarWorkspaceViewModel? {
    let topLevelMatch = workspaceSidebarWorkspaceMatchesSearch(workspace, projectName: projectName, terms: terms)
    let matchingItems = workspace.items.compactMap { workspaceSidebarFilteredItem($0, terms: terms) }
    if topLevelMatch || !matchingItems.isEmpty {
        return WorkspaceSidebarWorkspaceViewModel(
            name: workspace.name,
            projectId: workspace.projectId,
            folderId: workspace.folderId,
            displayName: workspace.displayName,
            sidebarLabel: workspace.sidebarLabel,
            isGeneratedName: workspace.isGeneratedName,
            tabSummary: workspace.tabSummary,
            monitorScopeId: workspace.monitorScopeId,
            monitorName: workspace.monitorName,
            isFocused: workspace.isFocused,
            isVisible: workspace.isVisible,
            items: matchingItems.isEmpty ? workspace.items : matchingItems,
        )
    }
    return nil
}

private func workspaceSidebarFilteredItem(
    _ item: WorkspaceSidebarItemViewModel,
    terms: [String],
) -> WorkspaceSidebarItemViewModel? {
    switch item.kind {
        case .window(let window):
            return workspaceSidebarWindowMatchesSearch(window, terms: terms)
                ? item
                : nil
        case .tabGroup(var group):
            let matchingTabs = group.tabs.filter {
                workspaceSidebarWindowMatchesSearch($0, terms: terms)
            }
            if !matchingTabs.isEmpty {
                group.searchVisibleTabs = matchingTabs
                return WorkspaceSidebarItemViewModel(kind: .tabGroup(group))
            }
            return workspaceSidebarSearchTextMatches([group.title], terms: terms)
                ? item
                : nil
    }
}

private func workspaceSidebarWindowMatchesSearch(
    _ window: WorkspaceSidebarWindowViewModel,
    terms: [String],
) -> Bool {
    workspaceSidebarSearchTextMatches(
        [
            window.title,
            window.appName,
            window.appBundleId,
            window.appBundlePath,
            window.workspaceName,
        ],
        terms: terms,
    )
}

private func workspaceSidebarSearchTerms(_ query: String) -> [String] {
    query
        .split(whereSeparator: { $0.isWhitespace })
        .map { String($0).localizedLowercase }
        .filter { !$0.isEmpty }
}

private func workspaceSidebarWorkspaceMatchesSearch(
    _ workspace: WorkspaceSidebarWorkspaceViewModel,
    projectName: String?,
    terms: [String],
) -> Bool {
    workspaceSidebarSearchTextMatches(
        [
            workspace.displayName,
            workspace.sidebarLabel,
            workspace.tabSummary.title,
            workspace.tabSummary.subtitle,
            workspace.tabSummary.appBundleId,
            workspace.tabSummary.appBundlePath,
            workspace.name,
            workspace.monitorName,
            projectName,
        ],
        terms: terms,
    )
}

private func workspaceSidebarSearchTextMatches(_ values: [String?], terms: [String]) -> Bool {
    let searchableText = values
        .compactMap { $0?.localizedLowercase }
        .joined(separator: " ")
    return terms.allSatisfy { searchableText.contains($0) }
}
