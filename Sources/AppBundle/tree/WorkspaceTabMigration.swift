import AppKit
import Common

@MainActor
func migrateWorkspaceTabGroupsToWorkspaceTabs() {
    // Workspace tabs were a one-way compatibility path while window tab groups
    // were disabled.  Running it with window tabs enabled immediately tears
    // down a newly created stack on the next workspace reconciliation.
    guard !config.windowTabs.enabled else { return }
    var didMigrate = false
    for workspace in orderedWorkspacesForPresentation() {
        didMigrate = migrateTabGroups(in: workspace) || didMigrate
    }
    guard didMigrate else { return }
    winMuxWorkspaceState.pruneProjectWorkspaceIndexes()
    pruneEmptyWorkspaces()
    ensureVisibleActiveProjectWorkspaces()
    checkWorkspaceHierarchyInvariants(requireActiveMonitorViewports: true)
}

@MainActor
@discardableResult
private func migrateTabGroups(in workspace: Workspace) -> Bool {
    migrateTabGroups(in: workspace.rootTilingContainer, sourceWorkspace: workspace)
}

@MainActor
@discardableResult
private func migrateTabGroups(in container: TilingContainer, sourceWorkspace: Workspace) -> Bool {
    var didMigrate = false
    for child in container.children.compactMap({ $0 as? TilingContainer }) {
        didMigrate = migrateTabGroups(in: child, sourceWorkspace: sourceWorkspace) || didMigrate
    }
    guard container.layout == .tabGroup else { return didMigrate }
    guard container.children.count > 1 else {
        normalizeLegacySingleTabGroupShell(container)
        return true
    }
    splitTabGroupIntoWorkspaceTabs(container, sourceWorkspace: sourceWorkspace)
    return true
}

@MainActor
private func normalizeLegacySingleTabGroupShell(_ tabGroup: TilingContainer) {
    guard tabGroup.layout == .tabGroup else { return }
    if tabGroup.isRootContainer {
        tabGroup.layout = .tiles
        return
    }
    guard tabGroup.children.count == 1,
          let onlyChild = tabGroup.children.first,
          let parent = tabGroup.parent
    else {
        tabGroup.layout = .tiles
        return
    }
    onlyChild.bind(
        to: parent,
        adaptiveWeight: tabGroup.getWeight(tabGroup.orientation),
        index: tabGroup.ownIndex ?? INDEX_BIND_LAST
    )
    _ = tabGroup.bind(to: NilTreeNode.instance, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
}

@MainActor
private func splitTabGroupIntoWorkspaceTabs(_ tabGroup: TilingContainer, sourceWorkspace: Workspace) {
    let tabChildren = tabGroup.children
    guard tabChildren.count > 1 else {
        tabGroup.layout = .tiles
        return
    }

    let activeChild = tabGroup.mostRecentChild ?? tabChildren.first.orDie()
    let insertionProjectId = workspaceProjectDefaultId
    let targetMonitor = sourceWorkspace.workspaceMonitor
    let tabGroupParent = tabGroup.parent as? TilingContainer
    let tabGroupIndex = tabGroup.ownIndex ?? INDEX_BIND_LAST
    var migratedWorkspaceOrder: [Workspace] = []

    for child in tabChildren {
        if child === activeChild {
            migratedWorkspaceOrder.append(sourceWorkspace)
        } else {
            let workspace = createMigratedWorkspaceTab(
                sourceWorkspace: sourceWorkspace,
                projectId: insertionProjectId,
                monitor: targetMonitor,
            )
            migratedWorkspaceOrder.append(workspace)
            child.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
    }

    if tabGroup.isRootContainer {
        tabGroup.layout = .tiles
    } else {
        activeChild.bind(to: tabGroup.parent.orDie(), adaptiveWeight: WEIGHT_AUTO, index: tabGroup.ownIndex ?? INDEX_BIND_LAST)
        if tabGroup.children.isEmpty {
            _ = tabGroup.bind(to: NilTreeNode.instance, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
        } else {
            tabGroup.layout = .tiles
        }
        normalizeSingleChildContainerAroundMigratedTab(
            parent: tabGroupParent,
            previousIndex: tabGroupIndex,
        )
    }
    reorderMigratedWorkspaceTabs(migratedWorkspaceOrder, projectId: insertionProjectId)
}

@MainActor
private func createMigratedWorkspaceTab(
    sourceWorkspace: Workspace,
    projectId: WorkspaceProjectId,
    monitor: Monitor,
) -> Workspace {
    let workspace = Workspace.get(byName: nextAutomaticWorkspaceName(projectId: projectId, monitor: monitor))
    workspace.markAsAutomaticallyNamed()
    workspace.assignProject(projectId)
    workspace.seedMonitorIfNeeded(monitor)
    if let sourceLabel = config.workspaceSidebar.workspaceLabels[sourceWorkspace.name],
       !sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       config.workspaceSidebar.workspaceLabels[workspace.name] == nil
    {
        config.workspaceSidebar.workspaceLabels[workspace.name] = sourceLabel
    }
    return workspace
}

@MainActor
private func normalizeSingleChildContainerAroundMigratedTab(
    parent: TilingContainer?,
    previousIndex: Int,
) {
    guard let parent,
          !parent.isRootContainer,
          parent.children.count == 1,
          let onlyChild = parent.children.first,
          let grandParent = parent.parent
    else { return }
    onlyChild.bind(to: grandParent, adaptiveWeight: parent.getWeight(parent.orientation), index: previousIndex)
    _ = parent.bind(to: NilTreeNode.instance, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
}

@MainActor
private func reorderMigratedWorkspaceTabs(_ workspaces: [Workspace], projectId: WorkspaceProjectId) {
    let workspaceIds = workspaces.map(\.id)
    let anchor = winMuxWorkspaceState.workspaceFoldersById[WorkspaceFolderId(projectId)]?.workspaceOrder.first {
        !workspaceIds.contains($0)
    }
    winMuxWorkspaceState.reorderWorkspaces(workspaceIds, inProject: projectId, before: anchor)
}
