import Common
import Foundation

extension AgentOperation {
    @MainActor
    func apply(context: inout AgentApplyContext) async throws {
        switch self {
            case .focusWindow(let target):
                _ = try await target.resolveWindow()?.focusWindow()
            case .focusWorkspace(let workspace):
                _ = Workspace.existing(byName: workspace)?.focusWorkspace()
            case .moveWindowToWorkspace(let windowId, let workspace, let shouldFocus):
                applyMoveWindowToWorkspace(windowId, workspace: workspace, shouldFocus: shouldFocus)
            case .moveTabGroupToWorkspace(let tabGroupId, let workspace, let shouldFocus):
                applyMoveTabGroupToWorkspace(tabGroupId, workspace: workspace, shouldFocus: shouldFocus, context: context)
            case .swapPanes(let a, let b):
                guard let nodeA = a.resolveNode(context: context), let nodeB = b.resolveNode(context: context) else { return }
                swapNodes(nodeA, nodeB)
            case .placePane(let pane, let relation, let target):
                guard let source = pane.resolveNode(context: context), let target = target.resolveNode(context: context) else { return }
                placeAgentPane(source, relation: relation, target: target)
            case .createTabGroup(let tabGroupId, let workspace, let tabs, let activeWindowId):
                applyCreateTabGroup(tabGroupId, workspace: workspace, tabs: tabs, activeWindowId: activeWindowId, context: &context)
            case .addWindowToTabGroup(let windowId, let tabGroupId, let activeWindowId):
                applyAddWindowToTabGroup(windowId, tabGroupId: tabGroupId, activeWindowId: activeWindowId, context: context)
            case .moveWindowOutOfTabGroup(let windowId):
                guard let window = Window.get(byId: windowId) else { return }
                _ = removeWindowFromTabStack(window)
            case .setActiveTab(let tabGroupId, let windowId):
                applySetActiveTab(tabGroupId, windowId: windowId, context: context)
            case .setWinMuxFullscreen(let windowId, let value, let noOuterGaps):
                guard let window = Window.get(byId: windowId) else { return }
                window.isFullscreen = value
                window.noOuterGapsInFullscreen = noOuterGaps ?? window.noOuterGapsInFullscreen
                window.markAsMostRecentChild()
            case .setFloating(let windowId, let value):
                applySetFloating(windowId, value: value)
            case .closeWindow(let windowId, let quitAppIfLastWindow):
                try await applyCloseWindow(windowId, quitAppIfLastWindow: quitAppIfLastWindow)
            case .parkWindow(let pane, let workspace):
                applyParkWindow(pane, workspace: workspace, context: context)
            case .setPaneSize(let pane, let axis, let size):
                guard let node = pane.resolveNode(context: context) else { return }
                setAgentPaneSize(node, axis: axis, size: size)
            case .setWorkspaceLayout(let layout):
                try await layout.apply()
        }
    }

    @MainActor
    private func applyMoveWindowToWorkspace(_ windowId: UInt32, workspace: String, shouldFocus: Bool?) {
        guard let window = Window.get(byId: windowId) else { return }
        let targetWorkspace = getAgentTargetWorkspace(named: workspace, projectSource: window.nodeWorkspace, monitorSource: window)
        _ = agentMoveWindowToWorkspace(window, targetWorkspace, focusFollowsWindow: shouldFocus ?? false)
    }

    @MainActor
    private func applyMoveTabGroupToWorkspace(
        _ tabGroupId: String,
        workspace: String,
        shouldFocus: Bool?,
        context: AgentApplyContext,
    ) {
        guard let group = resolveAgentTabGroup(tabGroupId, context: context) else { return }
        let targetWorkspace = getAgentTargetWorkspace(named: workspace, projectSource: group.nodeWorkspace, monitorSource: group)
        let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
        group.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
        if shouldFocus ?? false { _ = group.mostRecentWindowRecursive?.focusWindow() }
    }

    @MainActor
    private func applyCreateTabGroup(
        _ _: String?,
        workspace _: String?,
        tabs _: [UInt32],
        activeWindowId _: UInt32?,
        context _: inout AgentApplyContext,
    ) {
        // Validation rejects this legacy operation. Keep apply inert too, so
        // Bypassed validation cannot recreate old top folders.
    }

    @MainActor
    private func applyAddWindowToTabGroup(
        _ _: UInt32,
        tabGroupId _: String,
        activeWindowId _: UInt32?,
        context _: AgentApplyContext,
    ) {
        // Validation rejects this legacy operation. Keep apply inert too, so
        // Bypassed validation cannot recreate old top folders.
    }

    @MainActor
    private func applySetActiveTab(_ _: String, windowId _: UInt32, context _: AgentApplyContext) {
        // Sidebar Tabs are selected by focusing their backing workspace.
        // Legacy top folder activation is intentionally disabled.
    }

    @MainActor
    private func applySetFloating(_ windowId: UInt32, value: Bool) {
        guard let window = Window.get(byId: windowId), let workspace = window.nodeWorkspace else { return }
        if value {
            window.bindAsFloatingWindow(to: workspace)
        } else if window.isFloating {
            let binding = workspaceAppendBindingData(targetWorkspace: workspace, index: INDEX_BIND_LAST)
            window.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
        }
    }

    @MainActor
    private func applyCloseWindow(_ windowId: UInt32, quitAppIfLastWindow: Bool?) async throws {
        if quitAppIfLastWindow ?? false {
            var args = CloseCmdArgs(rawArgs: [])
            args.windowId = windowId
            args.quitIfLastWindow = true
            _ = try await CloseCommand(args: args).run(.defaultEnv, .emptyStdin)
        } else {
            Window.get(byId: windowId)?.closeAxWindow()
        }
    }

    @MainActor
    private func applyParkWindow(_ pane: AgentPaneRef, workspace: String?, context: AgentApplyContext) {
        guard let node = pane.resolveNode(context: context), let sourceWindow = node.mostRecentWindowRecursive ?? node.anyLeafWindowRecursive else { return }
        let workspaceName = workspace ?? "__agent_parked"
        let targetWorkspace = getAgentTargetWorkspace(named: workspaceName, projectSource: node.nodeWorkspace, monitorSource: node)
        if node is Window, sourceWindow.isFloating {
            node.bind(to: targetWorkspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        } else {
            let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
            node.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
        }
    }

    @MainActor
    private func getAgentTargetWorkspace(named name: String, projectSource: Workspace?, monitorSource: TreeNode) -> Workspace {
        let existedBefore = Workspace.existing(byName: name) != nil
        let targetWorkspace = Workspace.get(byName: name)
        if !existedBefore {
            targetWorkspace.assignProject(projectSource?.projectId ?? focus.workspace.projectId)
        }
        targetWorkspace.seedMonitorIfNeeded(monitorSource.nodeMonitor ?? focus.workspace.workspaceMonitor)
        return targetWorkspace
    }
}
