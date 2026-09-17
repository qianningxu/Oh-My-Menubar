extension Workspace {
    @MainActor
    func agentPaneInfos() -> [AgentPaneInfo] {
        var result = floatingWindows.map(agentFloatingPaneInfo)
        visitAgentPaneInfos(rootTilingContainer, result: &result)
        return result
    }

    @MainActor
    private func visitAgentPaneInfos(_ node: TreeNode, result: inout [AgentPaneInfo]) {
        switch node.nodeCases {
            case .window(let window):
                result.append(agentWindowPaneInfo(window))
            case .tilingContainer(let container):
                if container.isWindowTabGroup {
                    result.append(agentTabGroupPaneInfo(container))
                } else {
                    for child in container.children {
                        visitAgentPaneInfos(child, result: &result)
                    }
                }
            case .workspace, .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosHiddenAppsWindowsContainer, .macosPopupWindowsContainer:
                break
        }
    }

    @MainActor
    private func agentFloatingPaneInfo(_ window: Window) -> AgentPaneInfo {
        AgentPaneInfo(
            paneId: "pane-\(window.windowId)",
            kind: .window,
            tab: workspaceDisplayName(name),
            workspace: name,
            windowId: window.windowId,
            tabGroupId: nil,
            label: window.app.name ?? window.app.rawAppBundleId ?? "Window \(window.windowId)",
            size: window.agentPaneSizingNode.agentSizeRatio,
            sizeAxis: window.agentPaneSizingNode.agentSizeAxis,
            frame: (window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect ?? window.lastAppliedLayoutVirtualRect).map(AgentRect.init),
        )
    }

    @MainActor
    private func agentWindowPaneInfo(_ window: Window) -> AgentPaneInfo {
        agentFloatingPaneInfo(window)
    }

    @MainActor
    private func agentTabGroupPaneInfo(_ container: TilingContainer) -> AgentPaneInfo {
        let tabGroupId = agentTabGroupId(container)
        return AgentPaneInfo(
            paneId: agentPaneIdForTabGroup(tabGroupId: tabGroupId),
            kind: .tabGroup,
            tab: workspaceDisplayName(name),
            workspace: name,
            windowId: nil,
            tabGroupId: tabGroupId,
            label: "Folder \(container.agentTabWindows.map(\.windowId))",
            size: container.agentSizeRatio,
            sizeAxis: container.agentSizeAxis,
            frame: (container.lastAppliedLayoutPhysicalRect ?? container.lastAppliedLayoutVirtualRect).map(AgentRect.init),
        )
    }
}
