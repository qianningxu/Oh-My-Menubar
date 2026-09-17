import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    func handleSectionDoubleClick() {
        guard shouldHandleWorkspaceSidebarRenameFromDoubleClick(
            isCompact: isCompact,
            isEditing: renamingWorkspaceName != nil,
            isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()
        ) else { return }
        onBeginRenameWorkspace()
    }

    func handleSectionClick() {
        guard allowsWorkspaceActivation else { return }
        if isInUseOnOtherDisplay {
            activeInUseOverrideWorkspaceName = workspace.name
            return
        }
        if shouldHandleWorkspaceSidebarActivation(
            isEditing: false,
            isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()
        ) {
            activeInUseOverrideWorkspaceName = nil
            onBeginWorkspaceActivation(workspace.name)
            actions.send(.selectWorkspace(workspace.name))
        }
    }

    func handleComposedHeaderTabClick(_ tab: WorkspaceSidebarWindowViewModel) {
        guard allowsWorkspaceActivation else { return }
        guard shouldHandleWorkspaceSidebarActivation(
            isEditing: false,
            isSidebarDragInProgress: isWorkspaceSidebarDragInProgress()
        ) else { return }
        if isInUseOnOtherDisplay {
            activeInUseOverrideWorkspaceName = workspace.name
            return
        }
        activeInUseOverrideWorkspaceName = nil
        onBeginWorkspaceActivation(workspace.name)
        actions.send(.selectWindow(tab.windowId))
    }

    func handlePayloadDrop(_ payload: WorkspaceSidebarDragPayload) {
        guard !workspaceSidebarPayload(payload, comesFromWorkspace: workspace.name) else {
            actions.send(.clearDropPreview)
            WindowDragCursorProxyPanel.shared.hide()
            return
        }
        switch payload {
            case .window(let windowId):
                actions.send(.moveWindow(windowId, toWorkspace: workspace.name))
            case .tabGroup(let representativeWindowId):
                actions.send(.moveTabGroup(representativeWindowId, toWorkspace: workspace.name))
        }
    }
}

@MainActor
private func workspaceSidebarPayload(_ payload: WorkspaceSidebarDragPayload, comesFromWorkspace workspaceName: String) -> Bool {
    workspaceSidebarPayloadSourceWorkspaceName(payload) == workspaceName
}

@MainActor
func workspaceSidebarPayloadSourceWorkspaceName(_ payload: WorkspaceSidebarDragPayload) -> String? {
    switch payload {
        case .window(let windowId):
            return Window.get(byId: windowId)?.nodeWorkspace?.name
        case .tabGroup(let representativeWindowId):
            guard let window = Window.get(byId: representativeWindowId) else { return nil }
            return dragSubjectNode(for: window, subject: .group).nodeWorkspace?.name
    }
}
